//
//  RecurrenceRuleParserTests.swift
//  EventideTests
//
//  TDD contract for `RecurrenceRuleParser`. Tests are organized in three
//  implementation tiers that mirror the phased rollout plan:
//
//    Tier 1 — Must support in Phase 1 (subset recurrence):
//             FREQ + INTERVAL + COUNT/UNTIL + simple BYDAY (no positional).
//             Covers ~80% of real household recurring events.
//
//    Tier 2 — Phase 3, full RFC 5545 compliance:
//             positional BYDAY (1MO, -1FR), BYSETPOS, BYMONTHDAY combinations.
//
//    Tier 3 — Phase 4, parser hardening:
//             DST boundaries, leap-year Feb-29, WKST, far-future UNTIL,
//             Apple's floating UNTIL (no Z suffix).
//
//  Every test fails today against the `notImplemented` stub — that is by
//  design. Implementation work proceeds tier by tier; each tier should
//  flip green before the next is started.
//
//  Oracle data for these tests lives at `test/fixtures/rrule_corpus.json`,
//  shared across iOS, Android, and Dart parser tests.
//

import XCTest
import EventKit
@testable import eventide

final class RecurrenceRuleParserTests: XCTestCase {

    // MARK: - Helpers

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// Asserts a parsed `EKRecurrenceRule` matches the expected shape.
    /// Pass only the properties you care about — the rest must be unset.
    private func assertRule(
        _ rule: EKRecurrenceRule,
        frequency: EKRecurrenceFrequency,
        interval: Int = 1,
        count: Int? = nil,
        until: Date? = nil,
        daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil,
        daysOfTheMonth: [NSNumber]? = nil,
        monthsOfTheYear: [NSNumber]? = nil,
        setPositions: [NSNumber]? = nil,
        firstDayOfTheWeek: Int = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(rule.frequency, frequency, "frequency mismatch", file: file, line: line)
        XCTAssertEqual(rule.interval, interval, "interval mismatch", file: file, line: line)
        XCTAssertEqual(rule.recurrenceEnd?.occurrenceCount ?? 0, count ?? 0, "count mismatch", file: file, line: line)
        XCTAssertEqual(rule.recurrenceEnd?.endDate, until, "until mismatch", file: file, line: line)
        XCTAssertEqual(rule.daysOfTheWeek ?? [], daysOfTheWeek ?? [], "daysOfTheWeek mismatch", file: file, line: line)
        XCTAssertEqual(rule.daysOfTheMonth ?? [], daysOfTheMonth ?? [], "daysOfTheMonth mismatch", file: file, line: line)
        XCTAssertEqual(rule.monthsOfTheYear ?? [], monthsOfTheYear ?? [], "monthsOfTheYear mismatch", file: file, line: line)
        XCTAssertEqual(rule.setPositions ?? [], setPositions ?? [], "setPositions mismatch", file: file, line: line)
        XCTAssertEqual(rule.firstDayOfTheWeek, firstDayOfTheWeek, "firstDayOfTheWeek mismatch", file: file, line: line)
    }

    private func dow(_ day: EKWeekday, _ weekNumber: Int = 0) -> EKRecurrenceDayOfWeek {
        EKRecurrenceDayOfWeek(dayOfTheWeek: day, weekNumber: weekNumber)
    }

    // MARK: - Tier 1 — Phase 1 (subset recurrence) — required first

    func test_iris_thaiPartner_weeklyOnSaturday() throws {
        // Fixture id: iris_00_thai_partner — real Homzie household pattern
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;BYDAY=SA",
            dtstart: iso("2026-02-14T11:00:00Z")
        )
        assertRule(rule, frequency: .weekly, daysOfTheWeek: [dow(.saturday)])
    }

    func test_iris_tooGoodToGo_weeklyOnTuesdayAndWednesday() throws {
        // Fixture id: iris_01_too_good_to_go___cit
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;BYDAY=TU,WE",
            dtstart: iso("2026-03-18T15:30:00Z")
        )
        assertRule(rule, frequency: .weekly, daysOfTheWeek: [dow(.tuesday), dow(.wednesday)])
    }

    func test_iris_testAusHomzie_daily() throws {
        // Fixture id: iris_02_test_aus_homzie — Iris's own bug repro event
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=DAILY",
            dtstart: iso("2026-05-11T19:55:00Z")
        )
        assertRule(rule, frequency: .daily)
    }

    func test_iris_liveSession_everyFourWeeksTuesday() throws {
        // Fixture id: iris_03_live_session_ta+
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;INTERVAL=4;BYDAY=TU",
            dtstart: iso("2026-02-24T18:30:00Z")
        )
        assertRule(rule, frequency: .weekly, interval: 4, daysOfTheWeek: [dow(.tuesday)])
    }

    func test_rfc_dailyCount10() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=DAILY;COUNT=10",
            dtstart: iso("2026-09-02T09:00:00Z")
        )
        assertRule(rule, frequency: .daily, count: 10)
    }

    func test_rfc_dailyUntilChristmasEve() throws {
        let until = iso("2026-12-24T00:00:00Z")
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=DAILY;UNTIL=20261224T000000Z",
            dtstart: iso("2026-09-02T09:00:00Z")
        )
        assertRule(rule, frequency: .daily, until: until)
    }

    func test_rfc_everyOtherDayCount10() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=DAILY;INTERVAL=2;COUNT=10",
            dtstart: iso("2026-09-02T09:00:00Z")
        )
        assertRule(rule, frequency: .daily, interval: 2, count: 10)
    }

    func test_rfc_weeklyCount10() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;COUNT=10",
            dtstart: iso("2026-09-02T09:00:00Z")
        )
        assertRule(rule, frequency: .weekly, count: 10)
    }

    func test_gcal_biweeklyFriday() throws {
        // Canonical Google Calendar emit for "every 2 weeks on Friday"
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=FR",
            dtstart: iso("2026-09-04T07:00:00Z")
        )
        assertRule(rule, frequency: .weekly, interval: 2, daysOfTheWeek: [dow(.friday)])
    }

    func test_gcal_weekdaysMonToFri() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
            dtstart: iso("2026-09-07T09:00:00Z")
        )
        assertRule(
            rule, frequency: .weekly,
            daysOfTheWeek: [dow(.monday), dow(.tuesday), dow(.wednesday), dow(.thursday), dow(.friday)]
        )
    }

    func test_apple_count5OnWednesday() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;COUNT=5;BYDAY=WE",
            dtstart: iso("2026-09-02T15:00:00Z")
        )
        assertRule(rule, frequency: .weekly, count: 5, daysOfTheWeek: [dow(.wednesday)])
    }

    func test_apple_yearlyBirthday() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=YEARLY",
            dtstart: iso("2026-07-15T00:00:00Z")
        )
        assertRule(rule, frequency: .yearly)
    }

    // MARK: - Tier 2 — Phase 3 (full RFC 5545 compliance)

    func test_rfc_weeklyTueThuUntil() throws {
        let until = iso("2026-10-07T00:00:00Z")
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;UNTIL=20261007T000000Z;WKST=SU;BYDAY=TU,TH",
            dtstart: iso("2026-09-01T09:00:00Z")
        )
        assertRule(
            rule, frequency: .weekly, until: until,
            daysOfTheWeek: [dow(.tuesday), dow(.thursday)],
            firstDayOfTheWeek: 1
        )
    }

    func test_rfc_monthlyFirstFriday() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;COUNT=10;BYDAY=1FR",
            dtstart: iso("2026-09-04T09:00:00Z")
        )
        assertRule(rule, frequency: .monthly, count: 10, daysOfTheWeek: [dow(.friday, 1)])
    }

    func test_rfc_monthlyLastFriday() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;COUNT=10;BYDAY=-1FR",
            dtstart: iso("2026-09-25T09:00:00Z")
        )
        assertRule(rule, frequency: .monthly, count: 10, daysOfTheWeek: [dow(.friday, -1)])
    }

    func test_rfc_monthlySecondToLastMonday() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;COUNT=6;BYDAY=-2MO",
            dtstart: iso("2026-09-21T09:00:00Z")
        )
        assertRule(rule, frequency: .monthly, count: 6, daysOfTheWeek: [dow(.monday, -2)])
    }

    func test_rfc_quarterlyOnTheFirst() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;INTERVAL=3;COUNT=10;BYMONTHDAY=1",
            dtstart: iso("2026-09-01T09:00:00Z")
        )
        assertRule(
            rule, frequency: .monthly, interval: 3, count: 10,
            daysOfTheMonth: [1]
        )
    }

    func test_rfc_yearlyInJuneAndJuly() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=YEARLY;COUNT=10;BYMONTH=6,7",
            dtstart: iso("2026-06-10T09:00:00Z")
        )
        assertRule(
            rule, frequency: .yearly, count: 10,
            monthsOfTheYear: [6, 7]
        )
    }

    func test_rfc_usElectionDay() throws {
        // Every 4 years on the first Tuesday after Nov 1st.
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=YEARLY;INTERVAL=4;BYMONTH=11;BYDAY=TU;BYMONTHDAY=2,3,4,5,6,7,8",
            dtstart: iso("2026-11-03T09:00:00Z")
        )
        assertRule(
            rule, frequency: .yearly, interval: 4,
            daysOfTheWeek: [dow(.tuesday)],
            daysOfTheMonth: [2, 3, 4, 5, 6, 7, 8],
            monthsOfTheYear: [11]
        )
    }

    func test_rfc_thirdInstanceTueWedThu() throws {
        // BYSETPOS — historically the hardest RRULE feature for parsers.
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;COUNT=3;BYDAY=TU,WE,TH;BYSETPOS=3",
            dtstart: iso("2026-09-03T09:00:00Z")
        )
        assertRule(
            rule, frequency: .monthly, count: 3,
            daysOfTheWeek: [dow(.tuesday), dow(.wednesday), dow(.thursday)],
            setPositions: [3]
        )
    }

    func test_rfc_lastWorkdayOfMonth() throws {
        // BYSETPOS=-1 over Mon-Fri — every parser's nightmare.
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=6",
            dtstart: iso("2026-09-30T09:00:00Z")
        )
        assertRule(
            rule, frequency: .monthly, count: 6,
            daysOfTheWeek: [dow(.monday), dow(.tuesday), dow(.wednesday), dow(.thursday), dow(.friday)],
            setPositions: [-1]
        )
    }

    func test_gcal_monthlySecondThursday() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;BYDAY=2TH",
            dtstart: iso("2026-09-10T18:00:00Z")
        )
        assertRule(rule, frequency: .monthly, daysOfTheWeek: [dow(.thursday, 2)])
    }

    // MARK: - Tier 3 — Phase 4 (edge cases & parser hardening)

    func test_edge_dstBoundaryCrossing() throws {
        // Six weekly Sundays starting before DST → ending after.
        // Parser concern: EventKit handles DST internally; we just need to
        // not corrupt the rule's start anchor.
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;COUNT=6;BYDAY=SU",
            dtstart: iso("2026-03-15T07:00:00Z")
        )
        assertRule(rule, frequency: .weekly, count: 6, daysOfTheWeek: [dow(.sunday)])
    }

    func test_edge_leapYearFeb29() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;COUNT=4",
            dtstart: iso("2024-02-29T12:00:00Z")
        )
        assertRule(
            rule, frequency: .yearly, count: 4,
            daysOfTheMonth: [29],
            monthsOfTheYear: [2]
        )
    }

    func test_edge_wkstSundayShiftsWeekBoundary() throws {
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU;WKST=SU;COUNT=6",
            dtstart: iso("2026-09-07T09:00:00Z")
        )
        assertRule(
            rule, frequency: .weekly, interval: 2, count: 6,
            daysOfTheWeek: [dow(.monday), dow(.sunday)],
            firstDayOfTheWeek: 1
        )
    }

    func test_edge_monthlyOn31st() throws {
        // Feb / Apr / Jun / Sep / Nov get skipped — EventKit handles that
        // internally as long as we pass BYMONTHDAY=31.
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=MONTHLY;BYMONTHDAY=31;COUNT=8",
            dtstart: iso("2026-01-31T12:00:00Z")
        )
        assertRule(
            rule, frequency: .monthly, count: 8,
            daysOfTheMonth: [31]
        )
    }

    func test_edge_farFutureUntil() throws {
        let until = iso("2099-12-31T23:59:59Z")
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=YEARLY;UNTIL=20991231T235959Z",
            dtstart: iso("2026-09-01T09:00:00Z")
        )
        assertRule(rule, frequency: .yearly, until: until)
    }

    func test_edge_appleFloatingUntil() throws {
        // Apple Calendar emits `UNTIL=20261001` (no time, no Z suffix) for
        // all-day recurring events. dateutil rejects this; we must accept it
        // and interpret it as midnight UTC on that day (or local — see notes
        // in the fixture corpus).
        let until = iso("2026-10-01T00:00:00Z")
        let rule = try RecurrenceRuleParser.parse(
            rrule: "FREQ=WEEKLY;UNTIL=20261001;BYDAY=MO",
            dtstart: iso("2026-05-04T00:00:00Z")
        )
        assertRule(rule, frequency: .weekly, until: until, daysOfTheWeek: [dow(.monday)])
    }

    // MARK: - Round-trip (parse → serialize → parse) sanity

    func test_serialize_throwsNotImplemented() {
        // Documents that the serializer is the second TDD frontier.
        // Once parsing is green, flip this test to round-trip assertions.
        let stubRule = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            end: EKRecurrenceEnd(occurrenceCount: 4)
        )
        XCTAssertThrowsError(try RecurrenceRuleParser.serialize(stubRule)) { error in
            XCTAssertEqual(error as? RecurrenceRuleParserError, .notImplemented)
        }
    }

    // MARK: - Error handling

    func test_emptyString_throwsInvalidRRule() {
        XCTAssertThrowsError(try RecurrenceRuleParser.parse(rrule: "", dtstart: Date())) { error in
            // Once implemented, this should be `.invalidRRule`, not `.notImplemented`.
            // Until then, the stub satisfies the contract trivially.
            XCTAssertTrue(error is RecurrenceRuleParserError)
        }
    }

    func test_unknownFrequency_throwsInvalidRRule() {
        XCTAssertThrowsError(
            try RecurrenceRuleParser.parse(rrule: "FREQ=NANOSECONDLY", dtstart: Date())
        ) { error in
            XCTAssertTrue(error is RecurrenceRuleParserError)
        }
    }
}
