//
//  RecurrenceIntegrationTests.swift
//  EventideTests
//
//  End-to-end verification that the parser → EKRecurrenceRule path actually
//  produces correct occurrences when persisted into EventKit. The unit
//  RecurrenceRuleParserTests verify the parser builds the right
//  EKRecurrenceRule properties; these tests verify that EventKit then
//  expands those rules into the dates the corpus oracle predicts.
//
//  Permission strategy: tests create a **transient local-source EKCalendar**
//  on each setUp and tear it down. On iOS Simulator the .local source
//  historically allows creation without permission grant. If permission is
//  missing at runtime the setUp throws XCTSkip so the suite is reported as
//  skipped rather than failing — make sure to grant calendar access in
//  the simulator (Settings → Privacy → Calendars) before running locally.
//

import XCTest
import EventKit
@testable import eventide

final class RecurrenceIntegrationTests: XCTestCase {

    private var store: EKEventStore!
    private var testCalendar: EKCalendar!

    override func setUpWithError() throws {
        store = EKEventStore()

        // Request access — required since iOS 17 even for .local sources.
        let accessGranted = try waitForAccess()
        if !accessGranted {
            throw XCTSkip(
                "Calendar access not granted to the test bundle. " +
                "Grant in Settings → Privacy → Calendars (Simulator), " +
                "or run `xcrun simctl privacy <udid> grant calendar <bundle-id>`."
            )
        }

        guard let local = store.sources.first(where: { $0.sourceType == .local }) else {
            throw XCTSkip("No EKSource of type .local available on this simulator")
        }
        testCalendar = EKCalendar(for: .event, eventStore: store)
        testCalendar.title = "EventideRRULETest_\(UUID().uuidString.prefix(8))"
        testCalendar.cgColor = UIColor.systemBlue.cgColor
        testCalendar.source = local
        try store.saveCalendar(testCalendar, commit: true)
    }

    override func tearDownWithError() throws {
        if let cal = testCalendar {
            try? store.removeCalendar(cal, commit: true)
        }
        testCalendar = nil
        store = nil
    }

    // MARK: - Iris's real patterns

    func test_iris_thaiPartner_weeklySaturday_expandsCorrectly() throws {
        // Iris's wöchentliches Thai-Partner-Event. 8 occurrences from 2026-02-14
        // should land on consecutive Saturdays. Window covers ~10 weeks.
        try assertExpansion(
            rrule: "FREQ=WEEKLY;BYDAY=SA",
            dtstart: iso("2026-02-14T11:00:00Z"),
            windowDays: 60,
            expectedCount: 9,
            expectedFirstFive: [
                iso("2026-02-14T11:00:00Z"),
                iso("2026-02-21T11:00:00Z"),
                iso("2026-02-28T11:00:00Z"),
                iso("2026-03-07T11:00:00Z"),
                iso("2026-03-14T11:00:00Z"),
            ]
        )
    }

    func test_iris_liveSession_every4WeeksTuesday_expandsCorrectly() throws {
        try assertExpansion(
            rrule: "FREQ=WEEKLY;INTERVAL=4;BYDAY=TU",
            dtstart: iso("2026-02-24T18:30:00Z"),
            windowDays: 120,
            expectedCount: 5,
            expectedFirstFive: [
                iso("2026-02-24T18:30:00Z"),
                iso("2026-03-24T18:30:00Z"),
                iso("2026-04-21T18:30:00Z"),
                iso("2026-05-19T18:30:00Z"),
                iso("2026-06-16T18:30:00Z"),
            ]
        )
    }

    // MARK: - RFC canonicals

    func test_rfc_dailyCount10_terminatesAfter10Occurrences() throws {
        try assertExpansion(
            rrule: "FREQ=DAILY;COUNT=10",
            dtstart: iso("2026-09-02T09:00:00Z"),
            windowDays: 30,
            expectedCount: 10,
            expectedFirstFive: [
                iso("2026-09-02T09:00:00Z"),
                iso("2026-09-03T09:00:00Z"),
                iso("2026-09-04T09:00:00Z"),
                iso("2026-09-05T09:00:00Z"),
                iso("2026-09-06T09:00:00Z"),
            ]
        )
    }

    func test_gcal_biweeklyFriday_expandsCorrectly() throws {
        try assertExpansion(
            rrule: "FREQ=WEEKLY;INTERVAL=2;BYDAY=FR",
            dtstart: iso("2026-09-04T07:00:00Z"),
            windowDays: 50,
            expectedCount: 4,
            expectedFirstFive: [
                iso("2026-09-04T07:00:00Z"),
                iso("2026-09-18T07:00:00Z"),
                iso("2026-10-02T07:00:00Z"),
                iso("2026-10-16T07:00:00Z"),
            ]
        )
    }

    func test_rfc_quarterlyOnFirst_expandsByMonthDay() throws {
        try assertExpansion(
            rrule: "FREQ=MONTHLY;INTERVAL=3;COUNT=4;BYMONTHDAY=1",
            dtstart: iso("2026-09-01T09:00:00Z"),
            windowDays: 365,
            expectedCount: 4,
            expectedFirstFive: [
                iso("2026-09-01T09:00:00Z"),
                iso("2026-12-01T09:00:00Z"),
                iso("2027-03-01T09:00:00Z"),
                iso("2027-06-01T09:00:00Z"),
            ]
        )
    }

    // MARK: - Round-trip: rule survives create → retrieve cycle

    func test_recurrenceRule_isSurfacedOnRetrieve() throws {
        // Save an event with FREQ=WEEKLY;BYDAY=SA. After retrieving it
        // back, the serialized recurrenceRule string must round-trip.
        let dtstart = iso("2026-09-05T10:00:00Z")
        let originalRule = "FREQ=WEEKLY;BYDAY=SA"

        let ek = EKEvent(eventStore: store)
        ek.calendar = testCalendar
        ek.title = "RoundTrip"
        ek.startDate = dtstart
        ek.endDate = dtstart.addingTimeInterval(3600)
        ek.timeZone = TimeZone(identifier: "UTC")
        ek.recurrenceRules = [try RecurrenceRuleParser.parse(rrule: originalRule, dtstart: dtstart)]
        try store.save(ek, span: .thisEvent, commit: true)

        // Retrieve via the production code path
        let events = try store.events(matching: store.predicateForEvents(
            withStart: dtstart,
            end: dtstart.addingTimeInterval(86400 * 14),
            calendars: [testCalendar]
        )) as [EKEvent]
        // Predicate auto-expands, so we expect multiple EKEvent objects but
        // only one master — they all share calendarItemIdentifier.
        let masterId = ek.calendarItemIdentifier
        let firstMatch = events.first(where: { $0.calendarItemIdentifier == masterId })
        XCTAssertNotNil(firstMatch, "Saved master event was not returned by predicate")
        XCTAssertNotNil(firstMatch?.recurrenceRules?.first, "Master is missing its recurrenceRule")

        let serialized = try RecurrenceRuleParser.serialize(firstMatch!.recurrenceRules!.first!)
        XCTAssertEqual(serialized, originalRule,
                       "Round-trip through EventKit lost or transformed recurrence info")
    }

    // MARK: - Helpers

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    /// Drives an EKEventStore.requestFullAccess call synchronously with a 10s timeout.
    /// Returns false if permission was denied or the call timed out.
    private func waitForAccess() throws -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        // EKEventStore.requestFullAccessToEvents was introduced in iOS 17.
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { (g, _) in
                granted = g
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { (g, _) in
                granted = g
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return granted
    }

    /// Saves an event with the given RRULE, retrieves expanded occurrences in
    /// the requested window, and asserts the count + first 5 dates.
    private func assertExpansion(
        rrule: String,
        dtstart: Date,
        windowDays: Int,
        expectedCount: Int,
        expectedFirstFive: [Date],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let ek = EKEvent(eventStore: store)
        ek.calendar = testCalendar
        ek.title = "Test_\(rrule.prefix(20))"
        ek.startDate = dtstart
        ek.endDate = dtstart.addingTimeInterval(3600)
        // Anchor to UTC so EventKit's wall-clock-preservation doesn't drift
        // across DST boundaries (matches what EasyEventStore.createEvent does).
        ek.timeZone = TimeZone(identifier: "UTC")
        ek.recurrenceRules = [try RecurrenceRuleParser.parse(rrule: rrule, dtstart: dtstart)]
        try store.save(ek, span: .thisEvent, commit: true)

        let end = dtstart.addingTimeInterval(TimeInterval(windowDays * 86400))
        let predicate = store.predicateForEvents(withStart: dtstart, end: end, calendars: [testCalendar])
        let occurrences = store.events(matching: predicate)
            .map(\.startDate)
            .sorted()

        XCTAssertEqual(occurrences.count, expectedCount,
                       "expanded occurrence count mismatch for RRULE=\(rrule)",
                       file: file, line: line)

        let toCompare = min(expectedFirstFive.count, occurrences.count)
        for i in 0..<toCompare {
            XCTAssertEqual(occurrences[i], expectedFirstFive[i],
                           "occurrence #\(i) mismatch for RRULE=\(rrule)",
                           file: file, line: line)
        }
    }
}
