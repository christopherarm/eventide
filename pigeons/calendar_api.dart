// ignore: depend_on_referenced_packages
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/calendar_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/sncf/connect/tech/eventide/CalendarApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'sncf.connect.tech.eventide'),
    swiftOut: 'ios/eventide/Sources/eventide/CalendarApi.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'eventide',
  ),
)
@HostApi()
abstract class CalendarApi {
  @async
  @SwiftFunction('createCalendar(title:color:in:)')
  Calendar createCalendar({required String title, required int color, required Account? account});

  @async
  @SwiftFunction('retrieveCalendars(onlyWritable:from:)')
  List<Calendar> retrieveCalendars({required bool onlyWritableCalendars, required Account? account});

  @async
  List<Account> retrieveAccounts();

  @async
  @SwiftFunction('deleteCalendar(_:)')
  void deleteCalendar({required String calendarId});

  @async
  Event createEvent({
    required String calendarId,
    required String title,
    required int startDate,
    required int endDate,
    required bool isAllDay,
    required String? description,
    required String? url,
    required String? location,
    required List<int>? reminders,
    required String? recurrenceRule,
    required List<int>? excludedDates,
    required List<int>? recurrenceDates,
  });

  @async
  void createEventInDefaultCalendar({
    required String title,
    required int startDate,
    required int endDate,
    required bool isAllDay,
    required String? description,
    required String? url,
    required String? location,
    required List<int>? reminders,
    required String? recurrenceRule,
    required List<int>? excludedDates,
    required List<int>? recurrenceDates,
  });

  @async
  void createEventThroughNativePlatform({
    String? title,
    int? startDate,
    int? endDate,
    bool? isAllDay,
    String? description,
    String? url,
    String? location,
    List<int>? reminders,
    String? recurrenceRule,
    List<int>? excludedDates,
    List<int>? recurrenceDates,
  });

  /// Updates an existing event. All optional field params follow
  /// null-means-unchanged semantics; pass `""` to clear a string field.
  ///
  /// `span` controls how the change applies to recurring events:
  /// - `UpdateSpan.thisEvent`: modify only the occurrence at
  ///   `occurrenceTimeUtcMs`. On iOS this uses `EKSpan.thisEvent`;
  ///   on Android it inserts a detached child row.
  /// - `UpdateSpan.thisAndFuture`: terminate the master with UNTIL =
  ///   `occurrenceTimeUtcMs - 1ms` and write a new master at the
  ///   occurrence. Requires `occurrenceTimeUtcMs`.
  /// - `UpdateSpan.allEvents`: overwrite the master in-place; affects
  ///   every occurrence.
  ///
  /// `occurrenceTimeUtcMs` is required for `thisEvent` and `thisAndFuture`;
  /// ignored for `allEvents`.
  @async
  Event updateEvent({
    required String eventId,
    required UpdateSpan span,
    required int? occurrenceTimeUtcMs,
    required String? title,
    required int? startDate,
    required int? endDate,
    required bool? isAllDay,
    required String? description,
    required String? url,
    required String? location,
    required List<int>? reminders,
    required String? recurrenceRule,
    required List<int>? excludedDates,
    required List<int>? recurrenceDates,
  });

  @async
  List<Event> retrieveEvents({
    required String calendarId,
    required int startDate,
    required int endDate,
    required bool expandRecurring,
  });

  @async
  @SwiftFunction('deleteEvent(withId:)')
  void deleteEvent({required String eventId});

  @async
  @SwiftFunction('createReminder(_:forEventId:)')
  Event createReminder({required int reminder, required String eventId});

  @async
  @SwiftFunction('deleteReminder(_:withEventId:)')
  Event deleteReminder({required int reminder, required String eventId});

  @async
  Event createAttendee({
    required String eventId,
    required String name,
    required String email,
    required int role,
    required int type,
  });

  @async
  Event deleteAttendee({required String eventId, required String email});
}

final class Calendar {
  final String id;
  final String title;
  final int color;
  final bool isWritable;
  final Account account;

  const Calendar({
    required this.id,
    required this.title,
    required this.color,
    required this.isWritable,
    required this.account,
  });
}

final class Event {
  final String id;
  final String calendarId;
  final String title;
  final bool isAllDay;
  final int startDate;
  final int endDate;
  final List<int> reminders;
  final List<Attendee> attendees;
  final String? description;
  final String? url;
  final String? location;
  // RFC 5545 RRULE value (no "RRULE:" prefix), e.g. "FREQ=WEEKLY;BYDAY=MO".
  // Null for non-recurring events. Phase 1 grammar: FREQ, INTERVAL, COUNT,
  // UNTIL, BYDAY (non-positional), BYMONTHDAY, BYMONTH. See plan AD-1/AD-3.
  final String? recurrenceRule;
  // EXDATE values as ms-since-epoch UTC. Empty list when no exceptions.
  // Phase 1 iOS limitation: read-side surfaces empty list because EventKit
  // has no public EXDATE accessor; full round-trip on Android only.
  final List<int>? excludedDates;
  // RDATE values as ms-since-epoch UTC. Phase 2F: full round-trip on
  // Android via the CalendarContract.Events.RDATE column. iOS accepts on
  // write but ignores (parity with EXDATE) and always returns null on
  // read — EventKit has no public RDATE accessor.
  final List<int>? recurrenceDates;
  // For detached occurrences (events that were modified out of their
  // recurring series), points at the master event's id. Null for
  // non-detached events. iOS: EKEvent.isDetached == true. Android:
  // ORIGINAL_ID column on CalendarContract.Events.
  final String? originalEventId;
  // The original occurrence time (UTC ms-since-epoch) that this detached
  // event replaces. Null when not detached. iOS: derived from the
  // expanded master occurrence list (best-effort match). Android:
  // ORIGINAL_INSTANCE_TIME column.
  final int? originalInstanceTime;

  const Event({
    required this.id,
    required this.title,
    required this.isAllDay,
    required this.startDate,
    required this.endDate,
    required this.calendarId,
    required this.reminders,
    required this.attendees,
    required this.description,
    required this.url,
    required this.location,
    required this.recurrenceRule,
    required this.excludedDates,
    required this.recurrenceDates,
    required this.originalEventId,
    required this.originalInstanceTime,
  });
}

final class Account {
  final String id;
  final String name;
  final String type;

  const Account({required this.id, required this.name, required this.type});
}

final class Attendee {
  final String name;
  final String email;
  final int type;
  final int role;
  final int status;

  const Attendee({
    required this.name,
    required this.email,
    required this.role,
    required this.type,
    required this.status,
  });
}

/// Scope of an [CalendarApi.updateEvent] call.
enum UpdateSpan {
  /// Modify only the single occurrence at `occurrenceTimeUtcMs`.
  /// On iOS uses `EKSpan.thisEvent`; on Android inserts a detached row.
  thisEvent,

  /// Terminate the master series at `occurrenceTimeUtcMs` (exclusive) and
  /// write a new master starting at that time with the modified fields.
  thisAndFuture,

  /// Overwrite the master event in place; affects every occurrence.
  allEvents,
}
