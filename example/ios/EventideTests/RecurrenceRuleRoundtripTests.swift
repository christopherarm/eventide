//
//  RecurrenceRuleRoundtripTests.swift
//  EventideTests
//
//  Verifies that for every Phase 1 RRULE the parser produces an
//  EKRecurrenceRule whose serialization re-parses into a semantically
//  equivalent rule. Catches silent information loss on either side of
//  the parser↔serializer pair.
//
//  Note: serialize() normalizes some inputs (e.g. Apple's date-only
//  UNTIL `20261001` is re-emitted as `20261001T000000Z`). The round-trip
//  is semantically stable but not byte-for-byte stable in those cases —
//  the equivalence check uses ekRulesEqual(...) rather than string match.
//

import XCTest
import EventKit
@testable import eventide

final class RecurrenceRuleRoundtripTests: XCTestCase {

    private let anchor = ISO8601DateFormatter().date(from: "2026-09-02T09:00:00Z")!

    // MARK: - Iris (real Homzie data)

    func test_iris_thaiPartner_weeklySaturday() throws {
        try assertRoundtrip("FREQ=WEEKLY;BYDAY=SA")
    }

    func test_iris_tooGoodToGo_weeklyTueWed() throws {
        try assertRoundtrip("FREQ=WEEKLY;BYDAY=TU,WE")
    }

    func test_iris_testAusHomzie_daily() throws {
        try assertRoundtrip("FREQ=DAILY")
    }

    func test_iris_liveSession_every4WeeksTuesday() throws {
        try assertRoundtrip("FREQ=WEEKLY;INTERVAL=4;BYDAY=TU")
    }

    // MARK: - RFC 5545 canonicals (Tier 1 only)

    func test_rfc_dailyCount10() throws {
        try assertRoundtrip("FREQ=DAILY;COUNT=10")
    }

    func test_rfc_dailyUntilUtc() throws {
        try assertRoundtrip("FREQ=DAILY;UNTIL=20261224T000000Z")
    }

    func test_rfc_everyOtherDayCount10() throws {
        try assertRoundtrip("FREQ=DAILY;INTERVAL=2;COUNT=10")
    }

    func test_rfc_weeklyCount10() throws {
        try assertRoundtrip("FREQ=WEEKLY;COUNT=10")
    }

    func test_rfc_quarterlyOnFirst() throws {
        try assertRoundtrip("FREQ=MONTHLY;INTERVAL=3;COUNT=10;BYMONTHDAY=1")
    }

    func test_rfc_yearlyJunJul() throws {
        try assertRoundtrip("FREQ=YEARLY;COUNT=10;BYMONTH=6,7")
    }

    // MARK: - Google / Apple emit patterns

    func test_gcal_biweeklyFriday() throws {
        try assertRoundtrip("FREQ=WEEKLY;INTERVAL=2;BYDAY=FR")
    }

    func test_gcal_weekdays() throws {
        try assertRoundtrip("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
    }

    func test_apple_yearlyBirthday() throws {
        try assertRoundtrip("FREQ=YEARLY")
    }

    // MARK: - Floating UNTIL normalization

    func test_appleFloatingUntil_normalizesToUtc() throws {
        // Apple all-day rule emits no Z/T. We accept it on parse but
        // canonicalize to UTC Z on serialize. Round-trip stays stable thereafter.
        let parsed = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;UNTIL=20261001;BYDAY=MO",
            dtstart: anchor
        )
        let serialized = try RecurrenceRuleParser.serialize(parsed)
        XCTAssertTrue(serialized.contains("UNTIL=20261001T000000Z"),
                      "Floating UNTIL should canonicalize to UTC Z: \(serialized)")
        // And the round-trip from canonical form must remain stable.
        try assertRoundtrip(serialized)
    }

    // MARK: - Phase 2A round-trips (positional BYDAY)

    func test_roundtrip_monthlyFirstFriday() throws {
        try assertRoundtrip("FREQ=MONTHLY;COUNT=10;BYDAY=1FR")
    }

    func test_roundtrip_monthlyLastFriday() throws {
        try assertRoundtrip("FREQ=MONTHLY;COUNT=10;BYDAY=-1FR")
    }

    func test_roundtrip_monthlySecondToLastMonday() throws {
        try assertRoundtrip("FREQ=MONTHLY;COUNT=6;BYDAY=-2MO")
    }

    func test_roundtrip_monthlySecondThursday() throws {
        try assertRoundtrip("FREQ=MONTHLY;BYDAY=2TH")
    }

    func test_serialize_emits_positionalByDay() throws {
        // Direct serializer call: rule built via EventKit init must emit canonical "-1FR".
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(dayOfTheWeek: .friday, weekNumber: -1)],
            daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
            end: nil
        )
        XCTAssertEqual(try RecurrenceRuleParser.serialize(rule), "FREQ=MONTHLY;BYDAY=-1FR")
    }

    // MARK: - Serializer refusals (Phase 2 features still deferred)

    func test_serialize_refuses_bySetPos() throws {
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1,
            daysOfTheWeek: [
                EKRecurrenceDayOfWeek(dayOfTheWeek: .monday, weekNumber: 0),
                EKRecurrenceDayOfWeek(dayOfTheWeek: .tuesday, weekNumber: 0),
            ],
            daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: [-1 as NSNumber],
            end: nil
        )
        XCTAssertThrowsError(try RecurrenceRuleParser.serialize(rule)) { error in
            guard case RecurrenceRuleParserError.unsupportedFeature = error else {
                XCTFail("Expected unsupportedFeature, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    /// parse → serialize → parse; assert resulting rules are equivalent.
    private func assertRoundtrip(
        _ rrule: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let parsed1 = try RecurrenceRuleParser.parse(rrule: rrule, dtstart: anchor)
        let serialized = try RecurrenceRuleParser.serialize(parsed1)
        let parsed2 = try RecurrenceRuleParser.parse(rrule: serialized, dtstart: anchor)
        XCTAssertTrue(
            ekRulesEqual(parsed1, parsed2),
            """
            Round-trip changed semantics.
            input:    \(rrule)
            output:   \(serialized)
            reparsed differs from parsed.
            """,
            file: file, line: line
        )
    }

    /// Compares two EKRecurrenceRules by every field we serialize.
    /// EventKit's `isEqual` is unreliable across instances; this helper
    /// gives us a deterministic predicate.
    private func ekRulesEqual(_ a: EKRecurrenceRule, _ b: EKRecurrenceRule) -> Bool {
        guard a.frequency == b.frequency else { return false }
        guard a.interval == b.interval else { return false }
        guard (a.recurrenceEnd?.occurrenceCount ?? 0) == (b.recurrenceEnd?.occurrenceCount ?? 0) else { return false }
        guard a.recurrenceEnd?.endDate == b.recurrenceEnd?.endDate else { return false }
        guard nsNumArraysEqual(a.daysOfTheMonth, b.daysOfTheMonth) else { return false }
        guard nsNumArraysEqual(a.monthsOfTheYear, b.monthsOfTheYear) else { return false }
        guard nsNumArraysEqual(a.weeksOfTheYear, b.weeksOfTheYear) else { return false }
        guard nsNumArraysEqual(a.daysOfTheYear, b.daysOfTheYear) else { return false }
        guard nsNumArraysEqual(a.setPositions, b.setPositions) else { return false }
        guard dayOfWeekArraysEqual(a.daysOfTheWeek, b.daysOfTheWeek) else { return false }
        return true
    }

    private func nsNumArraysEqual(_ a: [NSNumber]?, _ b: [NSNumber]?) -> Bool {
        return (a ?? []) == (b ?? [])
    }

    private func dayOfWeekArraysEqual(_ a: [EKRecurrenceDayOfWeek]?, _ b: [EKRecurrenceDayOfWeek]?) -> Bool {
        let aa = a ?? []
        let bb = b ?? []
        guard aa.count == bb.count else { return false }
        for (x, y) in zip(aa, bb) {
            if x.dayOfTheWeek != y.dayOfTheWeek || x.weekNumber != y.weekNumber {
                return false
            }
        }
        return true
    }
}
