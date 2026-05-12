import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart';

import 'package:eventide/eventide.dart';
import 'package:eventide/src/calendar_api.g.dart';

class _MockCalendarApi extends Mock implements CalendarApi {}

void main() {
  tz.initializeTimeZones();

  late _MockCalendarApi mockCalendarApi;
  late Eventide eventide;

  setUp(() {
    mockCalendarApi = _MockCalendarApi();
    eventide = Eventide(calendarApi: mockCalendarApi);
  });

  final location = getLocation('UTC');
  final anchor = TZDateTime(location, 2026, 9, 7, 9);
  final updatedEvent = Event(
    id: '1',
    title: 'Renamed',
    isAllDay: false,
    startDate: anchor.millisecondsSinceEpoch,
    endDate: anchor.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    calendarId: '1',
    description: null,
    url: null,
    location: null,
    reminders: [],
    attendees: [],
    recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
    excludedDates: null,
  );

  setUpAll(() {
    registerFallbackValue(UpdateSpan.allEvents);
  });

  group('Eventide.updateEvent', () {
    test('allEvents span passes through with null occurrenceTime', () async {
      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).thenAnswer((_) async => updatedEvent);

      final result = await eventide.updateEvent(
        eventId: '1',
        span: ETUpdateSpan.allEvents,
        title: 'Renamed',
      );

      expect(result.title, 'Renamed');
      verify(
        () => mockCalendarApi.updateEvent(
          eventId: '1',
          span: UpdateSpan.allEvents,
          occurrenceTimeUtcMs: null,
          title: 'Renamed',
          startDate: null,
          endDate: null,
          isAllDay: null,
          description: null,
          url: null,
          location: null,
          reminders: null,
          recurrenceRule: null,
          excludedDates: null,
        ),
      ).called(1);
    });

    test('thisEvent span passes occurrenceTime as UTC ms', () async {
      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).thenAnswer((_) async => updatedEvent);

      await eventide.updateEvent(
        eventId: '1',
        span: ETUpdateSpan.thisEvent,
        occurrenceTime: anchor,
        title: 'Detached',
      );

      verify(
        () => mockCalendarApi.updateEvent(
          eventId: '1',
          span: UpdateSpan.thisEvent,
          occurrenceTimeUtcMs: anchor.toUtc().millisecondsSinceEpoch,
          title: 'Detached',
          startDate: null,
          endDate: null,
          isAllDay: null,
          description: null,
          url: null,
          location: null,
          reminders: null,
          recurrenceRule: null,
          excludedDates: null,
        ),
      ).called(1);
    });

    test('thisAndFuture span maps span enum', () async {
      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).thenAnswer((_) async => updatedEvent);

      await eventide.updateEvent(
        eventId: '1',
        span: ETUpdateSpan.thisAndFuture,
        occurrenceTime: anchor,
      );

      final captured = verify(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: captureAny(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).captured;
      expect(captured.single, UpdateSpan.thisAndFuture);
    });

    test('converts reminders Duration to native minutes', () async {
      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).thenAnswer((_) async => updatedEvent);

      await eventide.updateEvent(
        eventId: '1',
        span: ETUpdateSpan.allEvents,
        reminders: [const Duration(minutes: 30), const Duration(hours: 1)],
      );

      final captured = verify(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: captureAny(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).captured;
      expect(captured.single, equals([30, 60]));
    });

    test('passes recurrenceRule and excludedDates through unchanged', () async {
      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).thenAnswer((_) async => updatedEvent);

      final exDates = [
        TZDateTime(location, 2026, 9, 14, 9),
        TZDateTime(location, 2026, 9, 21, 9),
      ];
      await eventide.updateEvent(
        eventId: '1',
        span: ETUpdateSpan.allEvents,
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
        excludedDates: exDates,
      );

      final result = verify(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: captureAny(named: 'recurrenceRule'),
          excludedDates: captureAny(named: 'excludedDates'),
        ),
      ).captured;
      expect(result[0], 'FREQ=WEEKLY;BYDAY=MO');
      expect(result[1], equals(exDates.map((d) => d.toUtc().millisecondsSinceEpoch).toList()));
    });

    test('rethrows ETException when CalendarApi fails', () async {
      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          occurrenceTimeUtcMs: any(named: 'occurrenceTimeUtcMs'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
          excludedDates: any(named: 'excludedDates'),
        ),
      ).thenThrow(PlatformException(code: 'NOT_FOUND', message: 'gone'));

      expect(
        () => eventide.updateEvent(
          eventId: '1',
          span: ETUpdateSpan.allEvents,
        ),
        throwsA(isA<ETNotFoundException>()),
      );
    });
  });
}
