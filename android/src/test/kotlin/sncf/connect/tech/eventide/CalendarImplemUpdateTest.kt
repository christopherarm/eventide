package sncf.connect.tech.eventide

import android.accounts.AccountManager
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import sncf.connect.tech.eventide.handler.CalendarActivityManager
import sncf.connect.tech.eventide.handler.IcsEventManager
import sncf.connect.tech.eventide.handler.PermissionHandler
import java.util.concurrent.CountDownLatch

/**
 * Phase 2D — behaviour tests for [CalendarImplem.updateEvent] and its
 * RRULE-terminator helper. Deep ContentResolver round-trips live in the
 * integration tier (iOS RecurrenceIntegrationTests + manual device runs);
 * here we cover the contract surface: permission gating, RRULE validation,
 * span/occurrenceTime mutual requirement, and the withUntil helper.
 */
class CalendarImplemUpdateTest {
    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var permissionHandler: PermissionHandler
    private lateinit var icsEventManager: IcsEventManager
    private lateinit var accountManager: AccountManager
    private lateinit var packageManager: PackageManager
    private lateinit var calendarImplem: CalendarImplem
    private lateinit var calendarActivityManager: CalendarActivityManager
    private lateinit var calendarContentUri: Uri
    private lateinit var eventContentUri: Uri
    private lateinit var remindersContentUri: Uri
    private lateinit var attendeesContentUri: Uri

    @BeforeEach
    fun setup() {
        context = mockk(relaxed = true)
        contentResolver = mockk(relaxed = true)
        permissionHandler = mockk(relaxed = true)
        icsEventManager = mockk(relaxed = true)
        accountManager = mockk(relaxed = true)
        packageManager = mockk(relaxed = true)
        calendarActivityManager = mockk(relaxed = true)
        calendarContentUri = mockk(relaxed = true)
        eventContentUri = mockk(relaxed = true)
        remindersContentUri = mockk(relaxed = true)
        attendeesContentUri = mockk(relaxed = true)

        calendarImplem = CalendarImplem(
            context,
            permissionHandler,
            calendarActivityManager,
            icsEventManager,
            accountManager,
            packageManager,
            contentResolver,
            calendarContentUri,
            eventContentUri,
            remindersContentUri,
            attendeesContentUri
        )
    }

    @Test
    fun `updateEvent fails fast when permission refused`() = runTest {
        every { permissionHandler.requestWritePermission(any()) } answers {
            firstArg<(Boolean) -> Unit>().invoke(false)
        }
        val latch = CountDownLatch(1)
        var resultCode: String? = null
        calendarImplem.updateEvent(
            eventId = "1", span = UpdateSpan.ALL_EVENTS,
            occurrenceTimeUtcMs = null,
            title = "x", startDate = null, endDate = null, isAllDay = null,
            description = null, url = null, location = null,
            reminders = null, recurrenceRule = null, excludedDates = null
        ) { result ->
            result.onFailure { resultCode = (it as? FlutterError)?.code }
            latch.countDown()
        }
        latch.await()
        assertEquals("ACCESS_REFUSED", resultCode)
    }

    @Test
    fun `updateEvent rejects invalid RRULE`() = runTest {
        every { permissionHandler.requestWritePermission(any()) } answers {
            firstArg<(Boolean) -> Unit>().invoke(true)
        }
        val latch = CountDownLatch(1)
        var resultCode: String? = null
        calendarImplem.updateEvent(
            eventId = "1", span = UpdateSpan.ALL_EVENTS,
            occurrenceTimeUtcMs = null,
            title = null, startDate = null, endDate = null, isAllDay = null,
            description = null, url = null, location = null,
            reminders = null,
            recurrenceRule = "FREQ=BOGUS", excludedDates = null
        ) { result ->
            result.onFailure { resultCode = (it as? FlutterError)?.code }
            latch.countDown()
        }
        latch.await()
        assertEquals("INVALID_RRULE", resultCode)
    }

    @Test
    fun `updateEvent requires occurrenceTime for THIS_EVENT span`() = runTest {
        every { permissionHandler.requestWritePermission(any()) } answers {
            firstArg<(Boolean) -> Unit>().invoke(true)
        }
        val latch = CountDownLatch(1)
        var resultCode: String? = null
        calendarImplem.updateEvent(
            eventId = "1", span = UpdateSpan.THIS_EVENT,
            occurrenceTimeUtcMs = null,
            title = "x", startDate = null, endDate = null, isAllDay = null,
            description = null, url = null, location = null,
            reminders = null, recurrenceRule = null, excludedDates = null
        ) { result ->
            result.onFailure { resultCode = (it as? FlutterError)?.code }
            latch.countDown()
        }
        latch.await()
        assertEquals("INVALID_ARGUMENT", resultCode)
    }

    @Test
    fun `updateEvent requires occurrenceTime for THIS_AND_FUTURE span`() = runTest {
        every { permissionHandler.requestWritePermission(any()) } answers {
            firstArg<(Boolean) -> Unit>().invoke(true)
        }
        val latch = CountDownLatch(1)
        var resultCode: String? = null
        calendarImplem.updateEvent(
            eventId = "1", span = UpdateSpan.THIS_AND_FUTURE,
            occurrenceTimeUtcMs = null,
            title = "x", startDate = null, endDate = null, isAllDay = null,
            description = null, url = null, location = null,
            reminders = null, recurrenceRule = null, excludedDates = null
        ) { result ->
            result.onFailure { resultCode = (it as? FlutterError)?.code }
            latch.countDown()
        }
        latch.await()
        assertEquals("INVALID_ARGUMENT", resultCode)
    }

    @Test
    fun `withUntil appends UNTIL when none present`() {
        val out = calendarImplem.withUntil("FREQ=WEEKLY;BYDAY=MO", "20261001T120000Z")
        assertTrue(out.contains("FREQ=WEEKLY"))
        assertTrue(out.contains("BYDAY=MO"))
        assertTrue(out.contains("UNTIL=20261001T120000Z"))
    }

    @Test
    fun `withUntil replaces existing UNTIL`() {
        val out = calendarImplem.withUntil(
            "FREQ=WEEKLY;UNTIL=20251231T235959Z;BYDAY=MO",
            "20261001T120000Z"
        )
        assertTrue(out.contains("UNTIL=20261001T120000Z"))
        assertTrue(!out.contains("UNTIL=20251231T235959Z"))
    }

    @Test
    fun `withUntil strips COUNT (mutually exclusive with UNTIL)`() {
        val out = calendarImplem.withUntil(
            "FREQ=DAILY;COUNT=10",
            "20261001T120000Z"
        )
        assertTrue(out.contains("FREQ=DAILY"))
        assertTrue(out.contains("UNTIL=20261001T120000Z"))
        assertTrue(!out.contains("COUNT="))
    }
}
