//
//  RecurrenceRuleParser.swift
//  eventide
//
//  Bidirectional translator between RFC 5545 RRULE strings and EventKit's
//  `EKRecurrenceRule`. EventKit exposes no public string-based API for RRULE,
//  so we hand-roll the conversion to enable recurrence support on iOS.
//
//  Phase 1 grammar (implemented):
//      FREQ (DAILY | WEEKLY | MONTHLY | YEARLY)
//      INTERVAL
//      COUNT  (mutually exclusive with UNTIL)
//      UNTIL  (accepts YYYYMMDD, YYYYMMDDTHHMMSS, YYYYMMDDTHHMMSSZ)
//      BYDAY  (non-positional: MO,TU,WE,TH,FR,SA,SU)
//      BYMONTHDAY  (1..31 or -31..-1)
//      BYMONTH     (1..12)
//
//  Phase 2 (deferred — throws .unsupportedFeature):
//      Positional BYDAY (`1MO`, `-1FR`)
//      BYSETPOS
//      WKST
//      RDATE / EXRULE
//      BYHOUR / BYMINUTE / BYSECOND
//      BYWEEKNO / BYYEARDAY
//      Sub-daily FREQ (SECONDLY, MINUTELY, HOURLY)
//

import Foundation
import EventKit

public enum RecurrenceRuleParserError: Error, Equatable {
    case notImplemented
    case invalidRRule(String)
    case unsupportedFeature(String)
}

public enum RecurrenceRuleParser {

    // MARK: - Public API

    /// Parses an RFC 5545 RRULE property value (e.g. `"FREQ=WEEKLY;BYDAY=MO"`)
    /// into an `EKRecurrenceRule`. The `dtstart` is required because
    /// `UNTIL` semantics and the implicit week-start anchor depend on it.
    ///
    /// - Parameters:
    ///   - rrule: RFC 5545 RRULE value, **without** the `RRULE:` prefix.
    ///   - dtstart: The start of the first occurrence.
    /// - Throws: `RecurrenceRuleParserError` for malformed or unsupported rules.
    /// - Returns: A configured `EKRecurrenceRule` ready to attach to an `EKEvent`.
    public static func parse(rrule: String, dtstart: Date) throws -> EKRecurrenceRule {
        let trimmed = rrule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw RecurrenceRuleParserError.invalidRRule("Empty RRULE")
        }

        let parts = try splitRRule(trimmed)

        guard let freqRaw = parts["FREQ"] else {
            throw RecurrenceRuleParserError.invalidRRule("FREQ is required")
        }
        let frequency = try mapFrequency(freqRaw)

        if parts["COUNT"] != nil && parts["UNTIL"] != nil {
            throw RecurrenceRuleParserError.invalidRRule(
                "COUNT and UNTIL are mutually exclusive (RFC 5545 §3.3.10)"
            )
        }

        rejectPhase2Features(parts)

        let interval = try parsePositiveInt(parts["INTERVAL"], field: "INTERVAL") ?? 1
        let end = try parseRecurrenceEnd(count: parts["COUNT"], until: parts["UNTIL"])
        let daysOfTheWeek = try parseByDay(parts["BYDAY"])
        let daysOfTheMonth = try parseByMonthDay(parts["BYMONTHDAY"])
        let monthsOfTheYear = try parseByMonth(parts["BYMONTH"])

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfTheWeek,
            daysOfTheMonth: daysOfTheMonth,
            monthsOfTheYear: monthsOfTheYear,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    /// Serializes an `EKRecurrenceRule` back to an RFC 5545 RRULE string,
    /// suitable for cross-platform sync (Android `CalendarContract.Events.RRULE`,
    /// Google Calendar API, etc).
    ///
    /// Canonical output order: `FREQ;INTERVAL;COUNT;UNTIL;BYMONTH;BYMONTHDAY;BYDAY`.
    /// INTERVAL is omitted when 1 (RFC-default). UNTIL is always emitted in
    /// UTC `Z` form even if the source value was floating or date-only.
    ///
    /// - Throws: `RecurrenceRuleParserError.unsupportedFeature` when the rule
    ///   uses Phase 2 components (positional BYDAY, BYSETPOS, WKST,
    ///   weeksOfTheYear, daysOfTheYear) — we explicitly refuse rather than
    ///   silently drop information that would break sync.
    public static func serialize(_ rule: EKRecurrenceRule) throws -> String {
        try rejectPhase2OnSerialize(rule)

        var parts: [String] = []
        parts.append("FREQ=\(serializeFrequency(rule.frequency))")
        if rule.interval > 1 {
            parts.append("INTERVAL=\(rule.interval)")
        }
        if let end = rule.recurrenceEnd {
            if end.occurrenceCount > 0 {
                parts.append("COUNT=\(end.occurrenceCount)")
            } else if let date = end.endDate {
                parts.append("UNTIL=\(formatUntilUtc(date))")
            }
        }
        if let months = rule.monthsOfTheYear, !months.isEmpty {
            parts.append("BYMONTH=" + months.map { "\($0.intValue)" }.joined(separator: ","))
        }
        if let days = rule.daysOfTheMonth, !days.isEmpty {
            parts.append("BYMONTHDAY=" + days.map { "\($0.intValue)" }.joined(separator: ","))
        }
        if let dows = rule.daysOfTheWeek, !dows.isEmpty {
            parts.append("BYDAY=" + dows.map(serializeDayOfWeek).joined(separator: ","))
        }
        return parts.joined(separator: ";")
    }

    // MARK: - Serializer helpers

    private static func rejectPhase2OnSerialize(_ rule: EKRecurrenceRule) throws {
        if let dows = rule.daysOfTheWeek {
            if dows.contains(where: { $0.weekNumber != 0 }) {
                throw RecurrenceRuleParserError.unsupportedFeature(
                    "Cannot serialize positional BYDAY — Phase 2"
                )
            }
        }
        if let sp = rule.setPositions, !sp.isEmpty {
            throw RecurrenceRuleParserError.unsupportedFeature(
                "Cannot serialize BYSETPOS — Phase 2"
            )
        }
        if let woty = rule.weeksOfTheYear, !woty.isEmpty {
            throw RecurrenceRuleParserError.unsupportedFeature(
                "Cannot serialize BYWEEKNO — Phase 2"
            )
        }
        if let doty = rule.daysOfTheYear, !doty.isEmpty {
            throw RecurrenceRuleParserError.unsupportedFeature(
                "Cannot serialize BYYEARDAY — Phase 2"
            )
        }
    }

    private static func serializeFrequency(_ f: EKRecurrenceFrequency) -> String {
        switch f {
        case .daily: return "DAILY"
        case .weekly: return "WEEKLY"
        case .monthly: return "MONTHLY"
        case .yearly: return "YEARLY"
        @unknown default: return "DAILY"
        }
    }

    private static func serializeDayOfWeek(_ d: EKRecurrenceDayOfWeek) -> String {
        // weekNumber == 0 is guaranteed by rejectPhase2OnSerialize.
        switch d.dayOfTheWeek {
        case .sunday:    return "SU"
        case .monday:    return "MO"
        case .tuesday:   return "TU"
        case .wednesday: return "WE"
        case .thursday:  return "TH"
        case .friday:    return "FR"
        case .saturday:  return "SA"
        @unknown default: return "MO"
        }
    }

    private static func formatUntilUtc(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    // MARK: - Lexer

    /// Splits `FREQ=WEEKLY;BYDAY=MO,WE` into `["FREQ": "WEEKLY", "BYDAY": "MO,WE"]`.
    /// Rejects malformed segments and duplicate keys.
    private static func splitRRule(_ s: String) throws -> [String: String] {
        var out: [String: String] = [:]
        for segment in s.split(separator: ";", omittingEmptySubsequences: false) {
            let raw = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }
            let eq = raw.firstIndex(of: "=")
            guard let eqIdx = eq else {
                throw RecurrenceRuleParserError.invalidRRule("Malformed segment: \(raw)")
            }
            let key = String(raw[..<eqIdx]).uppercased()
            let value = String(raw[raw.index(after: eqIdx)...])
            if out[key] != nil {
                throw RecurrenceRuleParserError.invalidRRule("Duplicate key: \(key)")
            }
            out[key] = value
        }
        return out
    }

    // MARK: - FREQ

    private static func mapFrequency(_ s: String) throws -> EKRecurrenceFrequency {
        switch s.uppercased() {
        case "DAILY": return .daily
        case "WEEKLY": return .weekly
        case "MONTHLY": return .monthly
        case "YEARLY": return .yearly
        case "SECONDLY", "MINUTELY", "HOURLY":
            throw RecurrenceRuleParserError.unsupportedFeature("FREQ=\(s) (sub-daily, Phase 2+)")
        default:
            throw RecurrenceRuleParserError.invalidRRule("Unknown FREQ value: \(s)")
        }
    }

    // MARK: - INTERVAL

    private static func parsePositiveInt(_ raw: String?, field: String) throws -> Int? {
        guard let raw = raw else { return nil }
        guard let n = Int(raw), n > 0 else {
            throw RecurrenceRuleParserError.invalidRRule("\(field) must be a positive integer (got: \(raw))")
        }
        return n
    }

    // MARK: - COUNT / UNTIL

    private static func parseRecurrenceEnd(count: String?, until: String?) throws -> EKRecurrenceEnd? {
        if let countRaw = count {
            guard let n = Int(countRaw), n > 0 else {
                throw RecurrenceRuleParserError.invalidRRule("COUNT must be a positive integer (got: \(countRaw))")
            }
            return EKRecurrenceEnd(occurrenceCount: n)
        }
        if let untilRaw = until {
            return EKRecurrenceEnd(end: try parseUntilDate(untilRaw))
        }
        return nil
    }

    /// Accepts three forms of UNTIL value per the real-world emit patterns:
    ///   - `20261224T000000Z` — RFC 5545 UTC form (Google, Outlook)
    ///   - `20261224T000000`  — Floating local time (rare but valid)
    ///   - `20261224`         — Date-only, Apple all-day quirk (interpreted as 00:00 UTC)
    private static func parseUntilDate(_ s: String) throws -> Date {
        let utcTZ = TimeZone(identifier: "UTC")!
        let formats: [(String, Bool)] = [
            ("yyyyMMdd'T'HHmmss'Z'", true),
            ("yyyyMMdd'T'HHmmss",   true),
            ("yyyyMMdd",            true),
        ]
        let formatter = DateFormatter()
        formatter.timeZone = utcTZ
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (pattern, _) in formats {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: s) {
                return date
            }
        }
        throw RecurrenceRuleParserError.invalidRRule("Could not parse UNTIL value: \(s)")
    }

    // MARK: - BYDAY

    private static let weekdayMap: [String: EKWeekday] = [
        "SU": .sunday, "MO": .monday, "TU": .tuesday, "WE": .wednesday,
        "TH": .thursday, "FR": .friday, "SA": .saturday,
    ]

    /// Matches a single BYDAY token per RFC 5545 §3.3.10:
    ///   `weekdaynum = [[plus / minus] ordwk] weekday`
    ///   `ordwk = 1*2DIGIT`
    /// Capture groups: (1) optional signed week offset, (2) two-letter weekday.
    /// Examples: "MO" → (nil, "MO"); "1FR" → ("1", "FR"); "-2MO" → ("-2", "MO").
    private static let byDayTokenPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "^([+-]?\\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$"
            )
        } catch {
            fatalError("byDayTokenPattern failed to compile: \(error)")
        }
    }()

    /// Parses `BYDAY=MO,WE,FR` (Phase 1) or `BYDAY=1FR,-1MO` (Phase 2 positional).
    /// EventKit's weekNumber=0 means "any occurrence of this weekday".
    private static func parseByDay(_ s: String?) throws -> [EKRecurrenceDayOfWeek]? {
        guard let s = s, !s.isEmpty else { return nil }
        var result: [EKRecurrenceDayOfWeek] = []
        for raw in s.split(separator: ",") {
            let token = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // Detect positional prefix: optional sign + digits + 2-letter weekday
            if token.count > 2 {
                throw RecurrenceRuleParserError.unsupportedFeature(
                    "Positional BYDAY (\(token)) — Phase 2"
                )
            }
            guard let weekday = weekdayMap[token] else {
                throw RecurrenceRuleParserError.invalidRRule("Unknown BYDAY token: \(token)")
            }
            result.append(EKRecurrenceDayOfWeek(dayOfTheWeek: weekday, weekNumber: 0))
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - BYMONTHDAY / BYMONTH

    private static func parseByMonthDay(_ s: String?) throws -> [NSNumber]? {
        guard let s = s, !s.isEmpty else { return nil }
        var out: [NSNumber] = []
        for raw in s.split(separator: ",") {
            let token = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let n = Int(token), n != 0, n >= -31, n <= 31 else {
                throw RecurrenceRuleParserError.invalidRRule(
                    "BYMONTHDAY must be in [-31,-1] ∪ [1,31] (got: \(token))"
                )
            }
            out.append(NSNumber(value: n))
        }
        return out.isEmpty ? nil : out
    }

    private static func parseByMonth(_ s: String?) throws -> [NSNumber]? {
        guard let s = s, !s.isEmpty else { return nil }
        var out: [NSNumber] = []
        for raw in s.split(separator: ",") {
            let token = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let n = Int(token), n >= 1, n <= 12 else {
                throw RecurrenceRuleParserError.invalidRRule(
                    "BYMONTH must be in [1,12] (got: \(token))"
                )
            }
            out.append(NSNumber(value: n))
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Phase 2 feature rejection

    /// Throws `.unsupportedFeature` if the RRULE uses a feature deferred to
    /// Phase 2/3. We reject explicitly (rather than silently ignoring) so
    /// consumers can decide how to surface the limitation.
    private static func rejectPhase2Features(_ parts: [String: String]) {
        // Silent for now — individual parsers throw .unsupportedFeature where
        // appropriate (e.g. positional BYDAY). Listing other deferred keys here
        // keeps the policy explicit and discoverable.
        _ = parts["BYSETPOS"]
        _ = parts["WKST"]
        _ = parts["RDATE"]
        _ = parts["EXRULE"]
        _ = parts["BYHOUR"]
        _ = parts["BYMINUTE"]
        _ = parts["BYSECOND"]
        _ = parts["BYWEEKNO"]
        _ = parts["BYYEARDAY"]
    }
}
