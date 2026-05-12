//
//  EasyEventStore.swift
//  eventide
//
//  Created by CHOUPAULT Alexis on 31/12/2024.
//

import EventKit
import UIKit

final class EasyEventStore: EasyEventStoreProtocol {
    private let eventStore: EKEventStore
    private let eventEditManager: EventEditViewControllerManager
    
    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
        self.eventEditManager = EventEditViewControllerManager(eventStore: eventStore)
    }
    
    func createCalendar(title: String, color: UIColor, account: Account?) throws -> Calendar {
        guard let source = getSource(for: account) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Calendar source was not found",
                details: account != nil ? "No source has been found for account: \(account!.name)" : "No suitable calendar source found"
            )
        }
        
        let ekCalendar = EKCalendar(for: .event, eventStore: eventStore)
        
        ekCalendar.title = title
        ekCalendar.cgColor = color.cgColor
        ekCalendar.source = source
        
        do {
            try eventStore.saveCalendar(ekCalendar, commit: true)
            return ekCalendar.toCalendar()
            
        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "Error while saving calendar",
                details: error.localizedDescription
            )
        }
    }
    
    func retrieveCalendars(
        onlyWritable: Bool,
        from account: Account?
    ) -> [Calendar] {
        return eventStore.calendars(for: .event)
            .filter { onlyWritable ? $0.allowsContentModifications : true }
            .filter { calendar in
                guard let account = account else { return true }
                return account.id == calendar.source.sourceIdentifier && account.type == calendar.source.sourceType.toString()
            }
            .map { $0.toCalendar() }
    }
    
    func retrieveAccounts() -> [Account] {
        let sources = eventStore.sources
        
        return sources.compactMap { source in
            return Account(
                id: source.sourceIdentifier,
                name: source.title,
                type: source.sourceType.toString()
            )
        }
        // Remove duplicates by converting to Set and back to Array
        .reduce(into: [Account]()) { result, account in
            if !result.contains(where: { $0.name == account.name && $0.type == account.type }) {
                result.append(account)
            }
        }
    }
    
    func deleteCalendar(calendarId: String) throws {
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Calendar not found",
                details: "The provided calendar.id is certainly incorrect"
            )
        }
        
        guard calendar.allowsContentModifications else {
            throw PigeonError(
                code: "NOT_EDITABLE",
                message: "Calendar not editable",
                details: "Calendar does not allow content modifications"
            )
        }
            
        do {
            try eventStore.removeCalendar(calendar, commit: true)
            
        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "An error occurred",
                details: error.localizedDescription
            )
        }
    }
    
    func createEvent(
        calendarId: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        description: String?,
        url: String?,
        location: String?,
        timeIntervals: [TimeInterval]?,
        recurrenceRule: String?,
        excludedDates: [Int64]?
    ) throws -> Event {
        // Phase 1 iOS EXDATE limitation: EventKit has no public EXDATE accessor,
        // so excludedDates is accepted but not applied — detached-occurrence
        // semantics are Phase 2 (plan AD-3).
        _ = excludedDates

        let ekEvent = EKEvent(eventStore: eventStore)

        guard let ekCalendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Calendar not found",
                details: "The provided calendar.id is certainly incorrect"
            )
        }

        ekEvent.calendar = ekCalendar
        ekEvent.title = title
        ekEvent.notes = description
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.timeZone = TimeZone(identifier: "UTC")
        ekEvent.isAllDay = isAllDay
        ekEvent.alarms = timeIntervals?.compactMap({ EKAlarm(relativeOffset: $0) })
        ekEvent.location = location

        if url != nil {
            ekEvent.url = URL(string: url!)
        }

        if let rruleStr = recurrenceRule {
            do {
                let rule = try RecurrenceRuleParser.parse(rrule: rruleStr, dtstart: startDate)
                ekEvent.recurrenceRules = [rule]
            } catch let err as RecurrenceRuleParserError {
                throw PigeonError(
                    code: "INVALID_RRULE",
                    message: "Failed to parse recurrenceRule",
                    details: "\(err)"
                )
            }
        }

        do {
            try eventStore.save(ekEvent, span: EKSpan.thisEvent, commit: true)
            return ekEvent.toEvent()

        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "Event not created",
                details: nil
            )
        }
    }
    
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        description: String?,
        url: String?,
        location: String?,
        timeIntervals: [TimeInterval]?,
        recurrenceRule: String?,
        excludedDates: [Int64]?
    ) throws {
        // Phase 1: excludedDates not yet applied on default-calendar create path.
        _ = excludedDates

        let ekEvent = EKEvent(eventStore: eventStore)

        ekEvent.calendar = eventStore.defaultCalendarForNewEvents
        ekEvent.title = title
        ekEvent.notes = description
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.timeZone = TimeZone(identifier: "UTC")
        ekEvent.isAllDay = isAllDay
        ekEvent.alarms = timeIntervals?.compactMap({ EKAlarm(relativeOffset: $0) })
        ekEvent.location = location

        if url != nil {
            ekEvent.url = URL(string: url!)
        }

        if let rruleStr = recurrenceRule {
            do {
                let rule = try RecurrenceRuleParser.parse(rrule: rruleStr, dtstart: startDate)
                ekEvent.recurrenceRules = [rule]
            } catch let err as RecurrenceRuleParserError {
                throw PigeonError(
                    code: "INVALID_RRULE",
                    message: "Failed to parse recurrenceRule",
                    details: "\(err)"
                )
            }
        }

        do {
            try eventStore.save(ekEvent, span: EKSpan.thisEvent, commit: true)

        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "Event not created",
                details: nil
            )
        }
    }

    func presentEventCreationViewController(
        title: String?,
        startDate: Date?,
        endDate: Date?,
        isAllDay: Bool?,
        description: String?,
        url: String?,
        location: String?,
        timeIntervals: [TimeInterval]?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        eventEditManager.presentEventEditViewController(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            description: description,
            url: url,
            location: location,
            timeIntervals: timeIntervals,
            completion: completion
        )
    }
    
    func retrieveEvents(calendarId: String, startDate: Date, endDate: Date, expandRecurring: Bool) throws -> [Event] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Calendar not found",
                details: "The provided calendar.id is certainly incorrect"
            )
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: [calendar]
        )

        let rawEvents = eventStore.events(matching: predicate)
        if expandRecurring {
            return rawEvents.map { $0.toEvent(detachedMasters: nil) }
        }

        // Phase 2E: separate masters from detached occurrences. The predicate
        // returns both; we want to dedupe regular occurrences (which share
        // their master's calendarItemIdentifier) but keep every detached
        // event (each carries its own identifier and represents a user
        // edit). Master-only mode emits 1 row per series + N detached rows.
        var seenIdentifiers = Set<String>()
        var masters: [EKEvent] = []
        var detached: [EKEvent] = []
        for ekEvent in rawEvents {
            if ekEvent.isDetached {
                detached.append(ekEvent)
                continue
            }
            let identifier = ekEvent.calendarItemIdentifier
            if seenIdentifiers.insert(identifier).inserted {
                masters.append(ekEvent)
            }
        }
        return masters.map { $0.toEvent(detachedMasters: nil) }
            + detached.map { $0.toEvent(detachedMasters: masters) }
    }
    
    func updateEvent(
        eventId: String,
        span: EKSpan,
        occurrenceTime: Date?,
        title: String?,
        startDate: Date?,
        endDate: Date?,
        isAllDay: Bool?,
        description: String?,
        url: String?,
        location: String?,
        timeIntervals: [TimeInterval]?,
        recurrenceRule: String?,
        excludedDates: [Int64]?
    ) throws -> Event {
        // For `.thisEvent` and `.futureEvents` spans on recurring events we
        // need the specific occurrence handle (not the master). `allEvents`
        // (mapped to `.thisEvent` on the master) works directly on the master
        // because the master IS the source-of-truth for the series.
        let ekEvent: EKEvent
        if let occurrenceTime = occurrenceTime {
            guard let found = findOccurrence(eventId: eventId, occurrenceTime: occurrenceTime) else {
                throw PigeonError(
                    code: "NOT_FOUND",
                    message: "Occurrence not found",
                    details: "No occurrence at \(occurrenceTime) for series \(eventId)"
                )
            }
            ekEvent = found
        } else {
            guard let masterEvent = retrieveMasterWithRecurrence(eventId: eventId) else {
                throw PigeonError(
                    code: "NOT_FOUND",
                    message: "Event not found",
                    details: "The provided event.id is certainly incorrect"
                )
            }
            ekEvent = masterEvent
        }

        guard ekEvent.calendar.allowsContentModifications else {
            throw PigeonError(
                code: "NOT_EDITABLE",
                message: "Calendar not editable",
                details: "The calendar related to this event does not allow content modifications"
            )
        }

        // null → unchanged; empty string → clear (for description / url / location).
        if let title = title { ekEvent.title = title }
        if let isAllDay = isAllDay { ekEvent.isAllDay = isAllDay }
        if let startDate = startDate { ekEvent.startDate = startDate }
        if let endDate = endDate { ekEvent.endDate = endDate }
        if let description = description { ekEvent.notes = description.isEmpty ? nil : description }
        if let url = url { ekEvent.url = url.isEmpty ? nil : URL(string: url) }
        if let location = location { ekEvent.location = location.isEmpty ? nil : location }
        if let rruleStr = recurrenceRule {
            if rruleStr.isEmpty {
                ekEvent.recurrenceRules = nil
            } else {
                do {
                    let rule = try RecurrenceRuleParser.parse(rrule: rruleStr, dtstart: ekEvent.startDate)
                    ekEvent.recurrenceRules = [rule]
                } catch let err as RecurrenceRuleParserError {
                    throw PigeonError(
                        code: "INVALID_RRULE",
                        message: "Failed to parse recurrenceRule",
                        details: "\(err)"
                    )
                }
            }
        }
        if let timeIntervals = timeIntervals {
            ekEvent.alarms = timeIntervals.compactMap { EKAlarm(relativeOffset: $0) }
        }
        // Phase 2E will surface excludedDates round-trip on iOS; accepted-but-unused
        // here for parity with the createEvent signature.
        _ = excludedDates

        // iOS 26 quirk: saving a recurring master with `.thisEvent` silently
        // strips its recurrenceRule (detaches it into a one-off). When the
        // caller targets the master directly (occurrenceTime == nil) and the
        // event has a rule, use `.futureEvents` to preserve the series.
        let effectiveSpan: EKSpan = (occurrenceTime == nil
            && ekEvent.hasRecurrenceRules
            && span == .thisEvent)
            ? .futureEvents
            : span

        do {
            try eventStore.save(ekEvent, span: effectiveSpan, commit: true)
            // EventKit can rebuild the EKEvent reference internally during
            // save (especially for .futureEvents which splits the series).
            // Re-fetch via predicate so the returned Event reflects the
            // post-commit state with eagerly-loaded recurrenceRules — Apple
            // doesn't surface them on the basic event(withIdentifier:) path.
            let fresh = retrieveMasterWithRecurrence(eventId: ekEvent.eventIdentifier)
            return (fresh ?? ekEvent).toEvent()
        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "Event not updated",
                details: error.localizedDescription
            )
        }
    }

    /// Returns the master EKEvent with `recurrenceRules` populated.
    /// `EKEventStore.event(withIdentifier:)` alone returns a stripped handle
    /// where `recurrenceRules` is nil on iOS 16+ even for recurring masters.
    /// `events(matching:)` returns both the master AND expanded occurrences
    /// (all sharing the same `eventIdentifier`) — only the master has
    /// `recurrenceRules` populated. Pick that one.
    private func retrieveMasterWithRecurrence(eventId: String) -> EKEvent? {
        guard let basic = eventStore.event(withIdentifier: eventId) else { return nil }
        if basic.recurrenceRules?.isEmpty == false {
            return basic
        }
        let predicate = eventStore.predicateForEvents(
            withStart: basic.startDate,
            end: basic.startDate.addingTimeInterval(86400),
            calendars: [basic.calendar]
        )
        let candidates = eventStore.events(matching: predicate)
            .filter { $0.eventIdentifier == eventId }
        return candidates.first(where: { $0.recurrenceRules?.isEmpty == false })
            ?? candidates.first
            ?? basic
    }

    /// Locates the EKEvent instance for a specific occurrence by enumerating
    /// the series' calendar within a ±1 day window around `occurrenceTime`
    /// and picking the closest match by startDate. EventKit gives every
    /// occurrence the master's `calendarItemIdentifier`, so we filter by
    /// that to scope the search to this series.
    private func findOccurrence(eventId: String, occurrenceTime: Date) -> EKEvent? {
        guard let master = eventStore.event(withIdentifier: eventId) else { return nil }
        let windowStart = occurrenceTime.addingTimeInterval(-86400)
        let windowEnd = occurrenceTime.addingTimeInterval(86400)
        let predicate = eventStore.predicateForEvents(
            withStart: windowStart, end: windowEnd, calendars: [master.calendar]
        )
        let candidates = eventStore.events(matching: predicate)
            .filter { $0.calendarItemIdentifier == master.calendarItemIdentifier }
        return candidates.min(by: {
            abs($0.startDate.timeIntervalSince(occurrenceTime)) <
                abs($1.startDate.timeIntervalSince(occurrenceTime))
        })
    }

    func deleteEvent(eventId: String) throws {
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Event not found",
                details: "The provided event.id is certainly incorrect"
            )
        }
        
        guard event.calendar.allowsContentModifications else {
            throw PigeonError(
                code: "NOT_EDITABLE",
                message: "Calendar not editable",
                details: "The calendar related to this event does not allow content modifications"
            )
        }
            
        do {
            try eventStore.remove(event, span: .thisEvent)
            
        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "An error occurred",
                details: error.localizedDescription
            )
        }
    }
    
    func createReminder(timeInterval: TimeInterval, eventId: String) throws -> Event {
        guard let ekEvent = eventStore.event(withIdentifier: eventId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Event not found",
                details: "The provided event.id is certainly incorrect"
            )
        }
        
        let ekAlarm = EKAlarm(relativeOffset: timeInterval)
        if (ekEvent.alarms == nil) {
            ekEvent.alarms = [ekAlarm]
        } else {
            ekEvent.alarms!.append(ekAlarm)
        }

        do {
            try eventStore.save(ekEvent, span: EKSpan.thisEvent, commit: true)
            return ekEvent.toEvent()
            
        } catch {
            eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "An error occurred",
                details: error.localizedDescription
            )
        }
    }
    
    func deleteReminder(timeInterval: TimeInterval, eventId: String) throws -> Event {
        guard let ekEvent = eventStore.event(withIdentifier: eventId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Event not found",
                details: "The provided event.id is certainly incorrect"
            )
        }
        
        let alarmsToDelete = ekEvent.alarms?.filter({ $0.relativeOffset == timeInterval })
        
        guard let alarmsToDelete = alarmsToDelete, !alarmsToDelete.isEmpty else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Reminder not found",
                details: "The provided reminder is certainly incorrect"
            )
        }
        
        alarmsToDelete.forEach { ekEvent.removeAlarm($0) }
        
        do {
            try self.eventStore.save(ekEvent, span: EKSpan.thisEvent, commit: true)
            return ekEvent.toEvent()
            
        } catch {
            self.eventStore.reset()
            throw PigeonError(
                code: "GENERIC_ERROR",
                message: "An error occurred",
                details: error.localizedDescription
            )
        }
    }
    
    func retrieveAttendees(
        eventId: String
    ) throws -> [Attendee] {
        guard let ekEvent = eventStore.event(withIdentifier: eventId) else {
            throw PigeonError(
                code: "NOT_FOUND",
                message: "Event not found",
                details: "The provided event.id is certainly incorrect"
            )
        }
        
        var attendees: [Attendee] = []
        
        ekEvent.attendees?.forEach {
            attendees.append(
                Attendee(
                    name: $0.name ?? "",
                    email: "",
                    type: Int64($0.participantType.rawValue),
                    role: Int64($0.participantRole.rawValue),
                    status: Int64($0.participantStatus.rawValue)
                )
            )
        }
        
        return attendees
    }
    
    private func getSource(for account: Account? = nil) -> EKSource? {
        guard let defaultSource = eventStore.defaultCalendarForNewEvents?.source else {
            // if eventStore.defaultCalendarForNewEvents?.source is nil then eventStore.sources is empty
            return nil
        }
        
        if let account = account {
            if let specificSource = eventStore.sources.first(where: { $0.title == account.name && $0.sourceType.toString() == account.type && $0.sourceIdentifier == account.id }) {
                return specificSource
            }
        }
        
        let localSources = eventStore.sources.filter { $0.sourceType == .local }
        let iCloudSources = eventStore.sources.filter { 
            $0.sourceType == .calDAV && $0.title.contains("iCloud")
        }

        return localSources.first ?? iCloudSources.first ?? defaultSource
    }
}

fileprivate extension EKCalendar {
    func toCalendar() -> Calendar {
        Calendar(
            id: calendarIdentifier,
            title: title,
            color: UIColor(cgColor: cgColor).toInt64(),
            isWritable: allowsContentModifications,
            account: Account(
                id: source.sourceIdentifier,
                name: source.title,
                type: source.sourceType.toString()
            )
        )
    }
}

fileprivate extension EKEvent {
    /// Phase 2E: when called on a detached occurrence (`isDetached == true`),
    /// `detachedMasters` lets us locate the originating master event so we
    /// can surface `originalEventId`. Matching prefers a shared
    /// `calendarItemExternalIdentifier` (the iCalendar UID, identical for
    /// master and exceptions on CalDAV-synced calendars); falls back to the
    /// only master in the same calendar.
    /// `originalInstanceTime` is approximated by the detached event's
    /// `startDate` — EventKit doesn't expose RECURRENCE-ID publicly, so the
    /// consumer is responsible for date-matching back to the master's
    /// expanded series if precise alignment is needed.
    func toEvent(detachedMasters: [EKEvent]?) -> Event {
        let masterId: String?
        let originalInstanceMs: Int64?
        if isDetached, let masters = detachedMasters, !masters.isEmpty {
            let extId = calendarItemExternalIdentifier
            let matched: EKEvent? = {
                if let extId = extId {
                    if let m = masters.first(where: { $0.calendarItemExternalIdentifier == extId }) {
                        return m
                    }
                }
                let sameCal = masters.filter { $0.calendar.calendarIdentifier == calendar.calendarIdentifier }
                if sameCal.count == 1 {
                    return sameCal.first
                }
                return nil
            }()
            masterId = matched?.eventIdentifier
            originalInstanceMs = startDate.millisecondsSince1970
        } else {
            masterId = nil
            originalInstanceMs = nil
        }

        return Event(
            id: eventIdentifier,
            calendarId: calendar.calendarIdentifier,
            title: title,
            isAllDay: isAllDay,
            startDate: startDate.millisecondsSince1970,
            endDate: endDate.millisecondsSince1970,
            reminders: alarms?.map { Int64($0.relativeOffset) } ?? [],
            attendees: attendees?.compactMap {
                Attendee(
                    name: $0.name ?? "",
                    email: "",
                    type: Int64($0.participantType.rawValue),
                    role: Int64($0.participantRole.rawValue),
                    status: Int64($0.participantStatus.rawValue)
                )
            } ?? [],
            description: notes,
            url: url?.absoluteString,
            location: location,
            recurrenceRule: recurrenceRules?.first.flatMap { try? RecurrenceRuleParser.serialize($0) },
            excludedDates: nil,  // Phase 1 iOS limitation: EventKit has no public EXDATE accessor
            originalEventId: masterId,
            originalInstanceTime: originalInstanceMs
        )
    }

    /// Convenience overload for callers that don't have detached context
    /// (e.g. the EasyEventStore.createEvent / updateEvent return paths).
    /// The event might still be detached, but we won't be able to locate
    /// its master from a single-event reference, so the originalEventId
    /// stays nil.
    func toEvent() -> Event {
        return toEvent(detachedMasters: nil)
    }
}

fileprivate extension EKSource {
    func toAccount() -> Account {
        return Account(
            id: sourceIdentifier,
            name: title,
            type: sourceType.toString()
        )
    }
}

fileprivate extension EKSourceType {
     init?(from string: String) {
        switch string.lowercased() {
        case "local":
            self = .local
        case "caldav":
            self = .calDAV
        case "exchange":
            self = .exchange
        case "subscribed":
            self = .subscribed
        case "mobileme":
            self = .mobileMe
        case "birthdays":
            self = .birthdays
        default:
            return nil
        }
    }

    func toString() -> String {
        switch self {
        case .local:
            return "Local"
        case .calDAV:
            return "CalDAV"
        case .exchange:
            return "Exchange"
        case .subscribed:
            return "Subscribed"
        case .mobileMe:
            return "MobileMe"
        case .birthdays:
            return "Birthdays"
        @unknown default:
            return "Local"
        }
    }
}
