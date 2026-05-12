import 'package:eventide/src/calendar_api.g.dart';
import 'package:eventide/src/eventide_platform_interface.dart';
import 'package:eventide/src/extensions/attendee_extensions.dart';
import 'package:eventide/src/extensions/duration_extensions.dart';

extension EventToETEvent on Event {
  ETEvent toETEvent() {
    return ETEvent(
      id: id,
      title: title,
      isAllDay: isAllDay,
      startDate: DateTime.fromMillisecondsSinceEpoch(startDate),
      endDate: DateTime.fromMillisecondsSinceEpoch(endDate),
      calendarId: calendarId,
      description: description,
      url: url,
      location: location,
      reminders: reminders.toDurationList(),
      attendees: attendees.toETAttendeeList(),
      recurrenceRule: recurrenceRule,
      excludedDates: excludedDates
              ?.map((ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true))
              .toList() ??
          const [],
      originalEventId: originalEventId,
      originalInstanceTime: originalInstanceTime != null
          ? DateTime.fromMillisecondsSinceEpoch(originalInstanceTime!, isUtc: true)
          : null,
    );
  }
}

extension ETEventCopy on ETEvent {
  ETEvent copyWithReminders(Iterable<Duration>? reminders) {
    return ETEvent(
      id: id,
      title: title,
      isAllDay: isAllDay,
      startDate: startDate,
      endDate: endDate,
      calendarId: calendarId,
      description: description,
      url: url,
      location: location,
      reminders: reminders ?? this.reminders,
      attendees: attendees,
      recurrenceRule: recurrenceRule,
      excludedDates: excludedDates,
      originalEventId: originalEventId,
      originalInstanceTime: originalInstanceTime,
    );
  }
}

extension EventListToETEvent on List<Event> {
  List<ETEvent> toETEventList() {
    return map((e) => e.toETEvent()).toList();
  }
}

extension ETUpdateSpanToPigeon on ETUpdateSpan {
  UpdateSpan toPigeon() {
    switch (this) {
      case ETUpdateSpan.thisEvent:
        return UpdateSpan.thisEvent;
      case ETUpdateSpan.thisAndFuture:
        return UpdateSpan.thisAndFuture;
      case ETUpdateSpan.allEvents:
        return UpdateSpan.allEvents;
    }
  }
}
