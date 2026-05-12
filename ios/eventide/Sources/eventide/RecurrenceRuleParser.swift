//
//  RecurrenceRuleParser.swift
//  eventide
//
//  Bidirectional translator between RFC 5545 RRULE strings and EventKit's
//  `EKRecurrenceRule`. EventKit exposes no public string-based API for RRULE,
//  so we hand-roll the conversion to enable recurrence support on iOS.
//
//  Status: TDD skeleton. All entry points throw `.notImplemented`.
//  See `example/ios/EventideTests/RecurrenceRuleParserTests.swift` for the
//  test contract and `test/fixtures/rrule_corpus.json` for the oracle data.
//

import Foundation
import EventKit

public enum RecurrenceRuleParserError: Error, Equatable {
    case notImplemented
    case invalidRRule(String)
    case unsupportedFeature(String)
}

public enum RecurrenceRuleParser {

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
        throw RecurrenceRuleParserError.notImplemented
    }

    /// Serializes an `EKRecurrenceRule` back to an RFC 5545 RRULE string,
    /// suitable for cross-platform sync (Android `CalendarContract.Events.RRULE`,
    /// Google Calendar API, etc).
    ///
    /// - Throws: `RecurrenceRuleParserError` if the rule contains components
    ///           that have no RFC 5545 representation.
    public static func serialize(_ rule: EKRecurrenceRule) throws -> String {
        throw RecurrenceRuleParserError.notImplemented
    }
}
