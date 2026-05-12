## [Unreleased]

### Added — RRULE Phase 2A (positional BYDAY)
* iOS parser accepts RFC 5545 ordwk prefix on BYDAY tokens — `1FR`, `-1FR`, `2TH`, `-2MO`, etc. Range validated to `[-53,-1] ∪ [1,53]`.
* iOS serializer emits canonical positional form without leading `+` — `EKRecurrenceDayOfWeek(.friday, weekNumber: -1)` → `BYDAY=-1FR`.
* 4 previously-red parser tests turn green: `test_rfc_monthlyFirstFriday`, `test_rfc_monthlyLastFriday`, `test_rfc_monthlySecondToLastMonday`, `test_gcal_monthlySecondThursday`.
* 4 new round-trip tests in `RecurrenceRuleRoundtripTests.swift` plus an inverted serializer assertion (`test_serialize_emits_positionalByDay`).
* 3 new Android validator acceptance tests guard the lenient-by-design behavior.

### Added — RRULE Phase 2B (BYSETPOS)
* iOS parser handles `BYSETPOS=3,-1` (multi-value, range `[-366,-1] ∪ [1,366]`) and enforces RFC 5545 §3.3.10 (must accompany another BY-rule).
* iOS serializer emits BYSETPOS after BYDAY in canonical order.
* 2 previously-red parser tests turn green: `test_rfc_thirdInstanceTueWedThu`, `test_rfc_lastWorkdayOfMonth`.
* 3 new round-trip / direct-serialize tests; refusal test inverted.

### Added — RRULE Phase 2C (WKST)
* iOS parser maps `WKST=SU..SA` to `EKRecurrenceRule.firstDayOfTheWeek` via KVC (the property is get-only since iOS 16; the ObjC setter remains reachable).
* iOS serializer emits `WKST` after `BYSETPOS`, omitting when value is 0 (unset) or 2 (Monday, RFC default).
* 2 previously-red parser tests turn green: `test_rfc_weeklyTueThuUntil`, `test_edge_wkstSundayShiftsWeekBoundary`.
* 2 new round-trip tests + 2 new Android validator regression tests.

### Test state after Phase 2A + 2B + 2C
* iOS: **112 green / 0 red** (all 8 originally-red Phase 2 tests now green).
* Android: 25 validator tests green.
* The remaining Phase 2 / Phase 3 work (`updateEvent`, detached occurrences, RDATE, reverse-sync, BYWEEKNO, BYYEARDAY) is tracked in `fam_bowl` issue #43.

### Added — Phase 2D (updateEvent)
* New Pigeon `updateEvent` method + `UpdateSpan` enum (`thisEvent`, `thisAndFuture`, `allEvents`). Null-means-unchanged semantics on optional fields; pass `""` to clear a string field.
* **iOS** (`EasyEventStore.updateEvent`): applies non-nil mutations on the master or a specific occurrence (located via `predicateForEvents` ±1 day on `calendarItemIdentifier`). Two iOS 26 quirks worked around: `event(withIdentifier:)` returns a stripped EKEvent without `recurrenceRules` (we re-fetch via predicate and pick the candidate with rules); saving a recurring master with `EKSpan.thisEvent` silently strips the rule (we transparently promote to `.futureEvents` when modifying a master in-place). 6 integration tests across all three spans + null-vs-empty + NOT_FOUND path.
* **Android** (`CalendarImplem.updateEvent`): three-span dispatch — `ALL_EVENTS` updates the master row in place (handles the DURATION/DTEND coupling when start/end change), `THIS_EVENT` inserts a detached child row with `ORIGINAL_ID` + `ORIGINAL_INSTANCE_TIME`, `THIS_AND_FUTURE` terminates the master with `UNTIL = occurrence − 1 ms` (stripping any `COUNT`) and inserts a new master from the occurrence. 7 unit tests cover permission/validation gating + `withUntil` helper edge cases (replace, append, strip COUNT).
* **Dart** (`Eventide.updateEvent` + `ETUpdateSpan`): typed wrapper with DateTime/Duration mapping. 6 mocktail tests covering span mapping, occurrence-time conversion, reminders unit conversion, RRULE pass-through, and PlatformException → ETNotFoundException rethrow.

### Test state after Phase 2D
* iOS: **127 green / 0 red**.
* Android: 123 green / 0 red.
* Dart: 84 green / 0 red.

### Added — Phase 2F (RDATE round-trip on Android)
* Pigeon `Event` gains `recurrenceDates` (`List<int>?` UTC ms). ETEvent mirrors as `Iterable<DateTime>`. Same accept-on-write/ignore-on-iOS pattern as EXDATE: Android persists the column with full round-trip; iOS accepts the param for cross-platform parity but stores nothing (EventKit has no public RDATE accessor).
* **Android** (`CalendarImplem`): `createEvent` and `updateEvent` write the `CalendarContract.Events.RDATE` column when `recurrenceDates` is non-empty. `retrieveEvents` and the private `retrieveEvent` helper project `RDATE` and parse via the renamed `parseRfc5545DateList` helper (formerly `parseExdateList` — now shared between EXDATE and RDATE).
* **Dart** (`Eventide`): `createEvent`, `createEventInDefaultCalendar`, `createEventThroughNativePlatform`, and `updateEvent` accept `Iterable<DateTime>? recurrenceDates`, converted to UTC ms-since-epoch before the platform call. `EventToETEvent` populates the new field; `ETEventCopy.copyWithReminders` preserves it.
* Tests: 3 new Android Robolectric tests cover the renamed `parseRfc5545DateList` helper (RFC 5545 UTC datetime, Apple's date-only floating form, whitespace tolerance). 1 new Dart pigeon round-trip test verifies the field surfacing.

### Added — Phase 2E (detached occurrences on read)
* Pigeon `Event` gains `originalEventId` (String?) and `originalInstanceTime` (int? UTC ms) — non-null only for detached occurrences. ETEvent mirrors both, plus an `isDetached` convenience getter.
* **iOS** (`EasyEventStore.retrieveEvents`): splits the predicate result into masters (deduped by `calendarItemIdentifier`) and detached events (`isDetached == true`). Each detached entry gets `originalEventId` resolved by preferring a shared `calendarItemExternalIdentifier` (the iCalendar UID, identical on CalDAV-synced calendars) with a fallback to the only master in the same calendar. `originalInstanceTime` is the detached event's startDate as a best-effort approximation — EventKit doesn't expose RECURRENCE-ID publicly.
* **Android** (`CalendarImplem.retrieveEvents`): adds a second query after the master query that selects rows with `ORIGINAL_ID IN (master_ids)`, projecting `ORIGINAL_INSTANCE_TIME`. Full round-trip.
* Tests: new iOS integration test (`test_retrieveEvents_surfacesDetachedOccurrenceWithOriginalEventId`) exercises create-master → detach-occurrence → retrieve → assert. Suite totals: iOS **128 / 0**, Android **130 / 0**, Dart **84 / 0**.

## 2.2.0
* **Definitive fix in `createEventInDefaultCalendar` & `createEventThroughNativePlatform` on Android :**: using ical format under the hood

## 2.1.1
* **Fix allDay flag in createEventThroughNativePlatform:** allDay extra flag was `CalendarContract.EXTRA_EVENT_ALL_DAY` and not `CalendarContract.Events.ALL_DAY`

## 2.1.0
* **Account name improvement** on Android. We figured we could fetch a displayable account name based on the account type using PackageManager. i.e. `com.google` will result in a clean `Google` `account.name`
* **Dart dev dependencies upgrade**

## 2.0.1
* **Fix sourceType comparison** on iOS (https://github.com/sncf-connect-tech/eventide/issues/98)

## 2.0.0
* **🚨 BREAKING CHANGES - Account API Redesign:**
  * **createCalendar():** Parameter `localAccountName` (String) replaced with `account` (ETAccount?)
    * Before: `createCalendar(title: 'Work', color: Colors.red, localAccountName: 'My App')`
    * After: `createCalendar(title: 'Work', color: Colors.red, account: myAccount)`
    * When `account` is null, calendar is created in default account/source
  * **retrieveCalendars():** Parameter `fromLocalAccountName` (String) replaced with `account` (ETAccount?)
    * Before: `retrieveCalendars(fromLocalAccountName: 'My App')`
    * After: `retrieveCalendars(account: myAccount)`
  * **New Method:** Added `retrieveAccounts()` to get all available accounts (Google, Exchange, local, etc.)
    * Returns `Iterable<ETAccount>` with account details for better account management
    * Use this method to get accounts before creating calendars or filtering
* **Enhanced Account Management:**
  * More robust account handling across platforms
  * Better integration with system accounts (Google, Exchange, iCloud, etc.)
  * Improved account-based calendar filtering and organization
* **Migration Guide:**
  ```dart
  // OLD API (v1.x)
  final calendars = await eventide.retrieveCalendars(fromLocalAccountName: 'My App');
  await eventide.createCalendar(title: 'Work', color: Colors.red, localAccountName: 'My App');
  
  // NEW API (v2.0)
  final accounts = await eventide.retrieveAccounts();
  final myAccount = accounts.firstWhere((acc) => acc.name == 'My App');
  final calendars = await eventide.retrieveCalendars(account: myAccount);
  await eventide.createCalendar(title: 'Work', color: Colors.red, account: myAccount);
  ```
* **Removed automatic duration addition** for parameters `startDate` and `endDate` in `retrieveEvents()` method
* **Upcasting:**
  * **All `List` occurrences** are now `Iterable`
* Updates minimum supported SDK version to Flutter 3.29/Dart 3.7
* Add `location` to `ETEvent` by @StoneyDev

## 1.0.2
* **Android URL Support:** Added comprehensive URL handling for event creation and retrieval. Android Calendar API lacks native URL field support, so implemented intelligent description/URL merging system that preserves both fields while maintaining compatibility with existing calendar apps
* **Enhanced Native-Only Example App:** Added prefill parameters toggle to demonstrate `createEventThroughNativePlatform()` flexibility
  * New configuration switch to enable/disable parameter pre-population
  * Demonstrates both empty form (no parameters) and prefilled form usage patterns
  * Dynamic UI that adapts button text and success messages based on toggle state
  * Improved user experience for testing different API usage scenarios

## 1.0.1
* **Restored example app** as it was not appearing on pub.dev. Put the more complex examples in new `example/more-complex/` folder.

## 1.0.0+1
* **Restored ETNotSupportedByPlatform** as it was thrown by `createAttendee()` and `removeAttendee()` methods on iOS.
* **Splitted example app** into 3 "use-case" apps
* **Quickstart example** for pub.dev

## 1.0.0
* **Breaking Change - Android Permissions:** Removed default calendar permissions from eventide's `AndroidManifest.xml`. Apps must now declare needed permissions based on their usage:
  * `android.permission.READ_CALENDAR` for reading calendars/events
  * `android.permission.WRITE_CALENDAR` for creating/modifying calendars/events
  * No permissions required for `createEventInDefaultCalendar()` or `createEventThroughNativePlatform()` (use system Intent)
* **Android Enhancement:** `createEventInDefaultCalendar()` now uses system Intent to open calendar app directly (no permissions needed)
* **New Method:** Added `createEventThroughNativePlatform()` for platform-native event creation
  * iOS: Opens native event creation modal with write-only permission support
  * Android: Uses system calendar app (identical behavior to `createEventInDefaultCalendar()`)
  * All parameters optional for maximum flexibility
  * No permissions required in AndroidManifest.xml or Info.plist
* **Enhanced Exception Handling:** Added new specific exception types:
  * `ETUserCanceledException`: User canceled event creation in native platform
  * `ETPresentationException`: Event creation view cannot be presented
* **Removed Exception:** Removed unused `ETNotSupportedByPlatform` exception
* **Privacy-First Approach:** Enhanced documentation emphasizing user privacy and minimal permission requests
* **Android Bug Fix:** Fixed `allDay` attribute Boolean to Int cast in event creation
* **CI/CD Improvements:** Removed conditional CI jobs for better workflow reliability

## 0.10.2
* **Android fix:** `createEventInDefaultCalendar()` did not retrieve any default calendar when there was multiple primary calendars. Now also returns any writable calendar when there is no primary calendars

## 0.10.1
* **Fixed DateTime UTC handling** in `createEvent()`, `createEventInDefaultCalendar()` and `retrieveEvents()` by systemically calling `dateTime.toUtc()`

## 0.10.0
* **Changed signature of createEventInDefaultCalendar** to not return the created event as the event will not be editable

## 0.9.1
* **Fix** double (write-only and full) permission prompt issue on iOS by creating reminders in the same method channel as the event creation
* **Fix** permission issue on Android by binding PermissionHandler as a RequestPermissionsResultListener
* **Improved docs**

## 0.9.0
* **Removed retrieveDefaultCalendar** because it did not make sense to return a virtual calendar on iOS (error-prone)
* **Created createEventInDefaultCalendar** instead to directly create an event and prompt write-only access on iOS 17+
* **Created .pubignore file** to remove example app and other useless files from being published

## 0.8.1
* **Removed final clause** on Eventide class because it prevented it from being mocked

## 0.8.0
* **iOS 17 Support**: Added support for iOS 17 write-only calendar access
* **Permission Enhancement**: `retrieveDefaultCalendar()` now prompts for write-only access on iOS 17+
* **Documentation**: Comprehensive documentation update with detailed API reference
* **Platform Features**: Added dedicated section for platform-specific features

## 0.7.0
* **Android Calendar Fix**: Fixed calendar creation to use local accounts by default
* **Breaking Change**: `localAccountName` is now mandatory when creating calendars
* **Account Management**: Improved account handling for better calendar organization

## 0.6.0
* **Dependencies**: Removed dependency to [equatable](https://pub.dev/packages/equatable)
* **Pigeon Update**: Upgraded pigeon dependency to 25.2.0
* **Requirements**: Set minimum versions - Flutter 3.27.0 & Dart 3.6.0

## 0.5.0
* **Attendees Support**: Retrieve attendees through events (Android & iOS)
* **Attendee Management**: Create/delete attendees (Android only due to iOS EventKit limitations)
* **Development**: Set up lefthook & CI format check
* **Bug Fixes**: Fixed permission checks and configuration issues

## 0.4.0
* **iOS Enhancement**: Added Swift Package Manager support
* **Code Quality**: Updated to Dart 3.7.0 format standards

## 0.3.0
* **Reminders**: Create reminders alongside event creation
* **Bug Fix**: Fixed Android issue where name was incorrectly assigned to type field

## 0.2.0
* **Build Fix**: Resolved Gradle issue by targeting JVM 17
* **New Feature**: Exposed `ETAccount` class with name and type properties ([Issue #8](https://github.com/sncf-connect-tech/eventide/issues/8))
  * iOS: `name` = EKSource.sourceIdentifier, `type` = EKSource.sourceType
  * Android: `name` = CalendarContract.Calendars.ACCOUNT_NAME, `type` = CalendarContract.Calendars.ACCOUNT_TYPE

## 0.1.0
**Initial Release** 🎉

Core features:
* **Calendar Management**: Create, retrieve, and delete calendars
* **Event Management**: Create, retrieve, and delete events
* **Reminder System**: Create and delete reminders for events
* **Permission Handling**: Automatic system calendar permission management
* **Cross-Platform**: Full support for iOS and Android
* **Exception Handling**: Custom exceptions for better error management