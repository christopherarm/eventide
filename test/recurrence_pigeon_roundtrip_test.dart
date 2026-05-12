// Verifies that the new recurrenceRule / excludedDates fields on Pigeon's
// Event class survive the Dart → platform channel → Dart round-trip without
// information loss, and that EventToETEvent maps them correctly into ETEvent.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:eventide/eventide.dart';
import 'package:eventide/src/calendar_api.g.dart';
import 'package:eventide/src/extensions/event_extensions.dart';

class _MockCalendarApi extends Mock implements CalendarApi {}

void main() {
  late _MockCalendarApi mockCalendarApi;
  late Eventide eventide;

  final start = DateTime.utc(2026, 9, 2, 9);
  final end = start.add(const Duration(hours: 1));

  // Anchor event used as fallback for mocktail's registerFallbackValue.
  final anchorEvent = Event(
    id: 'anchor',
    title: 'anchor',
    isAllDay: false,
    startDate: 0,
    endDate: 0,
    calendarId: '1',
    reminders: const [],
    attendees: const [],
    recurrenceRule: null,
    excludedDates: null,
    recurrenceDates: null,
    originalEventId: null,
    originalInstanceTime: null,
  );

  setUpAll(() {
    registerFallbackValue(anchorEvent);
  });

  setUp(() {
    mockCalendarApi = _MockCalendarApi();
    eventide = Eventide(calendarApi: mockCalendarApi);
  });

  group('Event class — recurrenceRule + excludedDates round-trip', () {
    test('Pigeon Event round-trips recurrenceRule via toETEvent', () {
      final e = Event(
        id: '1',
        title: 'Weekly Thai Partner',
        isAllDay: false,
        startDate: start.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
        calendarId: 'cal1',
        reminders: const [],
        attendees: const [],
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=SA',
        excludedDates: null,
        recurrenceDates: null,
        originalEventId: null,
        originalInstanceTime: null,
      );
      final et = e.toETEvent();
      expect(et.recurrenceRule, 'FREQ=WEEKLY;BYDAY=SA');
      expect(et.excludedDates, isEmpty);
    });

    test('Pigeon Event round-trips recurrenceDates via toETEvent', () {
      final rdateMs = [
        DateTime.utc(2026, 10, 1, 9).millisecondsSinceEpoch,
        DateTime.utc(2026, 11, 5, 9).millisecondsSinceEpoch,
      ];
      final e = Event(
        id: '1',
        title: 'Weekly + RDATE additions',
        isAllDay: false,
        startDate: start.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
        calendarId: 'cal1',
        reminders: const [],
        attendees: const [],
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
        excludedDates: null,
        recurrenceDates: rdateMs,
        originalEventId: null,
        originalInstanceTime: null,
      );
      final et = e.toETEvent();
      expect(et.recurrenceDates.length, 2);
      expect(et.recurrenceDates.first.toUtc(), DateTime.utc(2026, 10, 1, 9));
      expect(et.recurrenceDates.last.toUtc(), DateTime.utc(2026, 11, 5, 9));
    });

    test('Pigeon Event round-trips excludedDates via toETEvent', () {
      final excludeMs = [
        DateTime.utc(2026, 10, 1, 9).millisecondsSinceEpoch,
        DateTime.utc(2026, 11, 5, 9).millisecondsSinceEpoch,
      ];
      final e = Event(
        id: '1',
        title: 'Skipped occurrences',
        isAllDay: false,
        startDate: start.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
        calendarId: 'cal1',
        reminders: const [],
        attendees: const [],
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=TH',
        excludedDates: excludeMs,
      );
      final et = e.toETEvent();
      expect(et.excludedDates.toList(), [
        DateTime.utc(2026, 10, 1, 9),
        DateTime.utc(2026, 11, 5, 9),
      ]);
    });

    test('Null recurrenceRule on Pigeon Event becomes null on ETEvent', () {
      final e = Event(
        id: '1',
        title: 'One-off',
        isAllDay: false,
        startDate: start.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
        calendarId: 'cal1',
        reminders: const [],
        attendees: const [],
        recurrenceRule: null,
        excludedDates: null,
      );
      final et = e.toETEvent();
      expect(et.recurrenceRule, isNull);
      expect(et.excludedDates, isEmpty);
    });
  });

  group('Eventide.createEvent — recurrenceRule propagation', () {
    test('Passes recurrenceRule through to CalendarApi', () async {
      // Given
      final returned = Event(
        id: '42',
        title: 'Weekly Saturday',
        isAllDay: false,
        startDate: start.millisecondsSinceEpoch,
        endDate: end.millisecondsSinceEpoch,
        calendarId: 'cal1',
        reminders: const [],
        attendees: const [],
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=SA',
        excludedDates: null,
      );
      when(() => mockCalendarApi.createEvent(
            calendarId: any(named: 'calendarId'),
            title: any(named: 'title'),
            isAllDay: any(named: 'isAllDay'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            description: any(named: 'description'),
            url: any(named: 'url'),
            location: any(named: 'location'),
            reminders: any(named: 'reminders'),
            recurrenceRule: any(named: 'recurrenceRule'),
            excludedDates: any(named: 'excludedDates'),
      recurrenceDates: any(named: 'recurrenceDates'),
          )).thenAnswer((_) async => returned);

      // When
      final result = await eventide.createEvent(
        calendarId: 'cal1',
        title: 'Weekly Saturday',
        startDate: start,
        endDate: end,
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=SA',
        excludedDates: [DateTime.utc(2026, 10, 1, 9)],
      );

      // Then
      expect(result.recurrenceRule, 'FREQ=WEEKLY;BYDAY=SA');
      // Verify the channel received the same RRULE and a single-entry EXDATE
      // as a UTC ms-since-epoch list.
      verify(() => mockCalendarApi.createEvent(
            calendarId: 'cal1',
            title: 'Weekly Saturday',
            isAllDay: false,
            startDate: start.millisecondsSinceEpoch,
            endDate: end.millisecondsSinceEpoch,
            description: null,
            url: null,
            location: null,
            reminders: null,
            recurrenceRule: 'FREQ=WEEKLY;BYDAY=SA',
            excludedDates: [DateTime.utc(2026, 10, 1, 9).millisecondsSinceEpoch],
            recurrenceDates: null,
          )).called(1);
    });
  });

  group('Eventide.retrieveEvents — expandRecurring opt-in', () {
    test('Defaults to expandRecurring=false (master-only mode)', () async {
      when(() => mockCalendarApi.retrieveEvents(
            calendarId: any(named: 'calendarId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            expandRecurring: any(named: 'expandRecurring'),
          )).thenAnswer((_) async => const []);

      await eventide.retrieveEvents(
        calendarId: 'cal1',
        startDate: start,
        endDate: end,
      );

      verify(() => mockCalendarApi.retrieveEvents(
            calendarId: 'cal1',
            startDate: start.millisecondsSinceEpoch,
            endDate: end.millisecondsSinceEpoch,
            expandRecurring: false,
          )).called(1);
    });

    test('Honors explicit expandRecurring=true', () async {
      when(() => mockCalendarApi.retrieveEvents(
            calendarId: any(named: 'calendarId'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            expandRecurring: any(named: 'expandRecurring'),
          )).thenAnswer((_) async => const []);

      await eventide.retrieveEvents(
        calendarId: 'cal1',
        startDate: start,
        endDate: end,
        expandRecurring: true,
      );

      verify(() => mockCalendarApi.retrieveEvents(
            calendarId: 'cal1',
            startDate: start.millisecondsSinceEpoch,
            endDate: end.millisecondsSinceEpoch,
            expandRecurring: true,
          )).called(1);
    });
  });
}
