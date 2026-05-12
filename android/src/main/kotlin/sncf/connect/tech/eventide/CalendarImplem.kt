package sncf.connect.tech.eventide

import android.accounts.AccountManager
import android.app.Activity
import android.app.Application
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import sncf.connect.tech.eventide.handler.CalendarActivityManager
import sncf.connect.tech.eventide.handler.DescriptionUrlHelper
import sncf.connect.tech.eventide.handler.IcsEventManager
import sncf.connect.tech.eventide.handler.PermissionHandler
import java.util.concurrent.CountDownLatch

class CalendarImplem(
    private val context: Context,
    private val permissionHandler: PermissionHandler = PermissionHandler(),
    private val calendarActivityManager: CalendarActivityManager = CalendarActivityManager(),
    private val icsEventManager: IcsEventManager = IcsEventManager(context),
    private val accountManager: AccountManager = AccountManager.get(context),
    private val packageManager: PackageManager = context.packageManager,
    private val contentResolver: ContentResolver = context.contentResolver,
    private val calendarContentUri: Uri = CalendarContract.Calendars.CONTENT_URI,
    private val eventContentUri: Uri = CalendarContract.Events.CONTENT_URI,
    private val remindersContentUri: Uri = CalendarContract.Reminders.CONTENT_URI,
    private val attendeesContentUri: Uri = CalendarContract.Attendees.CONTENT_URI,
): CalendarApi, EventidePlugin.ActivityComponent {
    private var activity: Activity? = null

    // ------------------- PluginActivityComponent implementation ------------------
    override val requestPermissionsResultListener: PluginRegistry.RequestPermissionsResultListener
        get() = permissionHandler
    
    override val calendarActivityLifecycleListener: Application.ActivityLifecycleCallbacks
        get() = calendarActivityManager
    
    override fun updateActivity(binding: ActivityPluginBinding?) {
        activity = binding?.activity
        permissionHandler.activity = activity
        calendarActivityManager.activity = activity
    }

    // ------------------- CalendarApi implementation ------------------
    override fun createCalendar(
        title: String,
        color: Long,
        account: Account?,
        callback: (Result<Calendar>) -> Unit
    ) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    // Use provided accountName or default to device name
                    val finalAccountName = account?.name ?: "local"

                    val syncAdapterUri = calendarContentUri.buildUpon()
                        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, finalAccountName)
                        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
                        .build()

                    val values = ContentValues().apply {
                        put(CalendarContract.Calendars.ACCOUNT_NAME, finalAccountName)
                        put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
                        put(CalendarContract.Calendars.NAME, title)
                        put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, title)
                        put(CalendarContract.Calendars.CALENDAR_COLOR, color)
                        put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
                        put(CalendarContract.Calendars.OWNER_ACCOUNT, finalAccountName)
                    }

                    val calendarUri = contentResolver.insert(syncAdapterUri, values)
                    if (calendarUri != null) {
                        val calendarId = calendarUri.lastPathSegment
                        if (calendarId != null) {
                            val calendar = Calendar(
                                id = calendarId,
                                title = title,
                                color = color,
                                isWritable = true,
                                account = Account(
                                    id = finalAccountName,
                                    name = finalAccountName,
                                    type = CalendarContract.ACCOUNT_TYPE_LOCAL
                                )
                            )
                            callback(Result.success(calendar))
                        } else {
                            callback(
                                Result.failure(
                                    FlutterError(
                                        code = "NOT_FOUND",
                                        message = "Failed to retrieve calendar ID. It might not have been created"
                                    )
                                )
                            )
                        }
                    } else {
                        callback(
                            Result.failure(
                                FlutterError(
                                    code = "GENERIC_ERROR",
                                    message = "Failed to create calendar"
                                )
                            )
                        )
                    }
                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun retrieveCalendars(
        onlyWritableCalendars: Boolean,
        account: Account?,
        callback: (Result<List<Calendar>>) -> Unit
    ) {
        permissionHandler.requestReadPermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestReadPermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val projection = arrayOf(
                        CalendarContract.Calendars._ID,
                        CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                        CalendarContract.Calendars.CALENDAR_COLOR,
                        CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
                        CalendarContract.Calendars.ACCOUNT_NAME,
                        CalendarContract.Calendars.ACCOUNT_TYPE
                    )

                    var selection: String? = null
                    var selectionArgs: Array<String>? = null

                    account?.let {
                        selection = CalendarContract.Calendars.ACCOUNT_NAME + " = ? AND " + CalendarContract.Calendars.ACCOUNT_TYPE + " = ?"
                        selectionArgs = arrayOf(it.name, it.type)
                    }

                    val cursor =
                        contentResolver.query(calendarContentUri, projection, selection, selectionArgs, null)
                    val calendars = mutableListOf<Calendar>()

                    cursor?.use {
                        while (it.moveToNext()) {
                            val id = it.getString(it.getColumnIndexOrThrow(CalendarContract.Calendars._ID))
                            val displayName = it.getString(it.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME))
                            val color = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_COLOR))
                            val accessLevel = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL))
                            val accountName = it.getString(it.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME))
                            val accountType = it.getString(it.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_TYPE))
                            val displayAccountName = getSystemAccountLabel(accountType) ?: accountName

                            val isWritable = accessLevel >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
                            if (!onlyWritableCalendars || isWritable) {
                                val calendar = Calendar(
                                    id = id,
                                    title = displayName,
                                    color = color,
                                    isWritable = isWritable,
                                    account = Account(
                                        id = accountName,
                                        name = displayAccountName,
                                        type = accountType
                                    )
                                )

                                calendars.add(calendar)
                            }
                        }
                    }

                    callback(Result.success(calendars))
                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }

        }
    }

    override fun retrieveAccounts(callback: (Result<List<Account>>) -> Unit) {
        permissionHandler.requestReadPermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestReadPermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val projection = arrayOf(
                        CalendarContract.Calendars.ACCOUNT_NAME,
                        CalendarContract.Calendars.ACCOUNT_TYPE
                    )

                    val cursor = contentResolver.query(
                        calendarContentUri,
                        projection,
                        null,
                        null,
                        null
                    )

                    val accountsSet = mutableSetOf<Account>()

                    cursor?.use {
                        while (it.moveToNext()) {
                            val accountName = it.getString(it.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME))
                            val accountType = it.getString(it.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_TYPE))
                            val displayAccountName = getSystemAccountLabel(accountType) ?: accountName

                            accountsSet.add(Account(
                                id = accountName,
                                name = displayAccountName,
                                type = accountType
                            ))
                        }
                    }

                    callback(Result.success(accountsSet.toList()))
                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun deleteCalendar(calendarId: String, callback: (Result<Unit>) -> Unit) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val selection = CalendarContract.Calendars._ID + " = ?"
                    val selectionArgs = arrayOf(calendarId)

                    if (isCalendarWritable(calendarId)) {
                        val deleted = contentResolver.delete(calendarContentUri, selection, selectionArgs)
                        if (deleted > 0) {
                            callback(Result.success(Unit))
                        } else {
                            callback(
                                Result.failure(
                                    FlutterError(
                                        code = "GENERIC_ERROR",
                                        message = "An error occurred during deletion"
                                    )
                                )
                            )
                        }
                    } else {
                        callback(
                            Result.failure(
                                FlutterError(
                                    code = "NOT_EDITABLE",
                                    message = "Calendar is not writable"
                                )
                            )
                        )
                    }

                } catch (e: FlutterError) {
                    callback(Result.failure(e))

                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun createEvent(
        calendarId: String,
        title: String,
        startDate: Long,
        endDate: Long,
        isAllDay: Boolean,
        description: String?,
        url: String?,
        location: String?,
        reminders: List<Long>?,
        recurrenceRule: String?,
        excludedDates: List<Long>?,
        recurrenceDates: List<Long>?,
        callback: (Result<Event>) -> Unit
    ) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            // Validate RRULE before any DB work — fail fast with clear error
            // rather than letting CalendarProvider silently accept garbage.
            if (recurrenceRule != null) {
                val v = RecurrenceRuleValidator.validate(recurrenceRule)
                if (v is RecurrenceRuleValidator.Result.Invalid) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "INVALID_RRULE",
                                message = "Invalid recurrenceRule",
                                details = v.reason,
                            )
                        )
                    )
                    return@requestWritePermission
                }
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    if (isCalendarWritable(calendarId)) {
                        val descriptionUrlHelper = DescriptionUrlHelper()
                        val mergedDescription = descriptionUrlHelper.mergeDescriptionAndUrl(description, url)

                        val eventValues = ContentValues().apply {
                            put(CalendarContract.Events.CALENDAR_ID, calendarId)
                            put(CalendarContract.Events.TITLE, title)
                            put(CalendarContract.Events.DESCRIPTION, mergedDescription)
                            put(CalendarContract.Events.EVENT_LOCATION, location)
                            put(CalendarContract.Events.DTSTART, startDate)
                            put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
                            put(CalendarContract.Events.ALL_DAY, isAllDay.toInt())
                        }
                        // Android schema constraint: recurring events MUST use DURATION,
                        // not DTEND. Plan-research finding #2.
                        if (recurrenceRule != null) {
                            val durationSec = (endDate - startDate) / 1000L
                            eventValues.put(CalendarContract.Events.DURATION, "PT${durationSec}S")
                            eventValues.put(CalendarContract.Events.RRULE, recurrenceRule)
                            if (!excludedDates.isNullOrEmpty()) {
                                eventValues.put(
                                    CalendarContract.Events.EXDATE,
                                    excludedDates.joinToString(",") { formatExdateUtc(it) }
                                )
                            }
                            // Phase 2F: RDATE column carries additional explicit
                            // occurrence dates beyond the RRULE expansion.
                            if (!recurrenceDates.isNullOrEmpty()) {
                                eventValues.put(
                                    CalendarContract.Events.RDATE,
                                    recurrenceDates.joinToString(",") { formatExdateUtc(it) }
                                )
                            }
                        } else {
                            eventValues.put(CalendarContract.Events.DTEND, endDate)
                        }

                        val eventUri = contentResolver.insert(eventContentUri, eventValues)
                        if (eventUri != null) {
                            val eventId = eventUri.lastPathSegment

                            if (reminders != null) {
                                val remindersLatch = CountDownLatch(reminders.size)
                                reminders.forEach { reminder ->
                                    val reminderValues = ContentValues().apply {
                                        put(CalendarContract.Reminders.EVENT_ID, eventId)
                                        put(CalendarContract.Reminders.MINUTES, reminder)
                                        put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                                    }
                                    contentResolver.insert(remindersContentUri, reminderValues)
                                    remindersLatch.countDown()
                                }
                                remindersLatch.await()
                            }

                            if (eventId != null) {
                                val event = Event(
                                    id = eventId,
                                    title = title,
                                    startDate = startDate,
                                    endDate = endDate,
                                    calendarId = calendarId,
                                    description = description,
                                    url = url,
                                    location = location,
                                    isAllDay = isAllDay,
                                    reminders = reminders ?: emptyList(),
                                    attendees = emptyList(),
                                    recurrenceRule = recurrenceRule,
                                    excludedDates = excludedDates,
                                    recurrenceDates = recurrenceDates,
                                )
                                callback(Result.success(event))
                            } else {
                                callback(
                                    Result.failure(
                                        FlutterError(
                                            code = "NOT_FOUND",
                                            message = "Failed to retrieve event ID"
                                        )
                                    )
                                )
                            }
                        } else {
                            callback(
                                Result.failure(
                                    FlutterError(
                                        code = "GENERIC_ERROR",
                                        message = "Failed to create event"
                                    )
                                )
                            )
                        }
                    } else {
                        callback(
                            Result.failure(
                                FlutterError(
                                    code = "NOT_EDITABLE",
                                    message = "Calendar is not writable"
                                )
                            )
                        )
                    }

                } catch (e: FlutterError) {
                    callback(Result.failure(e))

                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun createEventInDefaultCalendar(
        title: String,
        startDate: Long,
        endDate: Long,
        isAllDay: Boolean,
        description: String?,
        url: String?,
        location: String?,
        reminders: List<Long>?,
        recurrenceRule: String?,
        excludedDates: List<Long>?,
        recurrenceDates: List<Long>?,
        callback: (Result<Unit>) -> Unit
    ) {
        // The ICS share path doesn't surface recurrence at all yet; explicitly
        // accept the args to satisfy the Pigeon interface.
        @Suppress("UNUSED_VARIABLE") val r = recurrenceRule
        @Suppress("UNUSED_VARIABLE") val e = excludedDates
        @Suppress("UNUSED_VARIABLE") val d = recurrenceDates
        shareEventAsIcs(
            title = title, startDate = startDate, endDate = endDate, isAllDay = isAllDay,
            description = description, url = url, location = location, reminders = reminders,
            callback = callback
        )
    }

    override fun createEventThroughNativePlatform(
        title: String?,
        startDate: Long?,
        endDate: Long?,
        isAllDay: Boolean?,
        description: String?,
        url: String?,
        location: String?,
        reminders: List<Long>?,
        recurrenceRule: String?,
        excludedDates: List<Long>?,
        recurrenceDates: List<Long>?,
        callback: (Result<Unit>) -> Unit
    ) {
        @Suppress("UNUSED_VARIABLE") val r = recurrenceRule
        @Suppress("UNUSED_VARIABLE") val e = excludedDates
        @Suppress("UNUSED_VARIABLE") val d = recurrenceDates
        shareEventAsIcs(
            title = title, startDate = startDate, endDate = endDate, isAllDay = isAllDay,
            description = description, url = url, location = location, reminders = reminders,
            callback = callback
        )
    }

    override fun retrieveEvents(
        calendarId: String,
        startDate: Long,
        endDate: Long,
        expandRecurring: Boolean,
        callback: (Result<List<Event>>) -> Unit
    ) {
        // Phase 1: when expandRecurring=true the caller wants flattened
        // occurrences (the old CalendarContract.Instances behaviour). We do
        // not implement that yet — the default master-only path covers the
        // primary Homzie use case. Document and continue.
        @Suppress("UNUSED_VARIABLE") val phase1ExpandStub = expandRecurring
        permissionHandler.requestReadPermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestReadPermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val projection = arrayOf(
                        CalendarContract.Events._ID,
                        CalendarContract.Events.TITLE,
                        CalendarContract.Events.DESCRIPTION,
                        CalendarContract.Events.EVENT_LOCATION,
                        CalendarContract.Events.DTSTART,
                        CalendarContract.Events.DTEND,
                        CalendarContract.Events.EVENT_TIMEZONE,
                        CalendarContract.Events.ALL_DAY,
                        CalendarContract.Events.RRULE,
                        CalendarContract.Events.EXDATE,
                        CalendarContract.Events.RDATE,
                        CalendarContract.Events.DURATION,
                        CalendarContract.Events.LAST_DATE,
                        CalendarContract.Events.ORIGINAL_ID,
                    )
                    // Overlap query (plan AD-2): match series that intersect the
                    // window rather than series whose DTSTART falls inside it.
                    //   - DTSTART <= windowEnd      (series begins before window ends)
                    //   - LAST_DATE NULL OR >= windowStart   (series still active)
                    //   - ORIGINAL_ID IS NULL        (exclude detached exception children — Phase 2)
                    val selection =
                        "${CalendarContract.Events.CALENDAR_ID} = ? " +
                        "AND ${CalendarContract.Events.DTSTART} <= ? " +
                        "AND (${CalendarContract.Events.LAST_DATE} IS NULL OR ${CalendarContract.Events.LAST_DATE} >= ?) " +
                        "AND ${CalendarContract.Events.ORIGINAL_ID} IS NULL"
                    val selectionArgs = arrayOf(calendarId, endDate.toString(), startDate.toString())

                    val cursor = contentResolver.query(eventContentUri, projection, selection, selectionArgs, null)
                    val events = mutableListOf<Event>()

                    cursor?.use { c ->
                        val descriptionUrlHelper = DescriptionUrlHelper()
                        while (c.moveToNext()) {
                            val id = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events._ID))
                            val title = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events.TITLE))
                            val storedDescription =
                                c.getString(c.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION))
                            val (parsedDescription, parsedUrl) = descriptionUrlHelper.splitDescriptionAndUrl(storedDescription)
                            val eventLocation = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION))
                            val start = c.getLong(c.getColumnIndexOrThrow(CalendarContract.Events.DTSTART))
                            val rruleIdx = c.getColumnIndexOrThrow(CalendarContract.Events.RRULE)
                            val rrule = if (c.isNull(rruleIdx)) null else c.getString(rruleIdx)
                            val exdateIdx = c.getColumnIndexOrThrow(CalendarContract.Events.EXDATE)
                            val exdateRaw = if (c.isNull(exdateIdx)) null else c.getString(exdateIdx)
                            val rdateIdx = c.getColumnIndexOrThrow(CalendarContract.Events.RDATE)
                            val rdateRaw = if (c.isNull(rdateIdx)) null else c.getString(rdateIdx)
                            val durationIdx = c.getColumnIndexOrThrow(CalendarContract.Events.DURATION)
                            val duration = if (c.isNull(durationIdx)) null else c.getString(durationIdx)
                            // Recurring rows store DURATION instead of DTEND; compute first-occurrence end.
                            val end = if (rrule != null && duration != null) {
                                start + parseDurationToMs(duration)
                            } else {
                                val dtendIdx = c.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                                if (c.isNull(dtendIdx)) start else c.getLong(dtendIdx)
                            }
                            val excludedDates = exdateRaw?.let { parseRfc5545DateList(it) } ?: emptyList()
                            val recurrenceDates = rdateRaw?.let { parseRfc5545DateList(it) } ?: emptyList()
                            val isAllDay = c.getInt(c.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)).toBoolean()

                            val attendees = mutableListOf<Attendee>()
                            val attendeesLatch = CountDownLatch(1)
                            retrieveAttendees(id) { result ->
                                result.onSuccess {
                                    attendees.addAll(it)
                                    attendeesLatch.countDown()
                                }
                                result.onFailure { error ->
                                    callback(Result.failure(error))
                                }
                            }

                            val reminders = mutableListOf<Long>()
                            val remindersLatch = CountDownLatch(1)
                            retrieveReminders(id) { result ->
                                result.onSuccess {
                                    reminders.addAll(it)
                                    remindersLatch.countDown()
                                }
                                result.onFailure { error ->
                                    callback(Result.failure(error))
                                }
                            }

                            attendeesLatch.await()
                            remindersLatch.await()

                            events.add(
                                Event(
                                    id = id,
                                    title = title,
                                    startDate = start,
                                    endDate = end,
                                    calendarId = calendarId,
                                    description = parsedDescription,
                                    url = parsedUrl,
                                    location = eventLocation,
                                    isAllDay = isAllDay,
                                    reminders = reminders,
                                    attendees = attendees,
                                    recurrenceRule = rrule,
                                    excludedDates = excludedDates,
                                    recurrenceDates = recurrenceDates,
                                    originalEventId = null,
                                    originalInstanceTime = null,
                                )
                            )
                        }
                    }

                    // Phase 2E: second query — fetch detached exception children
                    // whose ORIGINAL_ID points at one of the master ids we just
                    // surfaced. Each detached child carries its own row in
                    // CalendarContract.Events with ORIGINAL_INSTANCE_TIME set
                    // to the time of the master occurrence it replaces.
                    val masterIds = events.map { it.id }
                    if (masterIds.isNotEmpty()) {
                        val detachedProjection = arrayOf(
                            CalendarContract.Events._ID,
                            CalendarContract.Events.TITLE,
                            CalendarContract.Events.DESCRIPTION,
                            CalendarContract.Events.EVENT_LOCATION,
                            CalendarContract.Events.DTSTART,
                            CalendarContract.Events.DTEND,
                            CalendarContract.Events.ALL_DAY,
                            CalendarContract.Events.ORIGINAL_ID,
                            CalendarContract.Events.ORIGINAL_INSTANCE_TIME,
                        )
                        val placeholders = masterIds.joinToString(",") { "?" }
                        val detachedSelection =
                            "${CalendarContract.Events.CALENDAR_ID} = ? " +
                            "AND ${CalendarContract.Events.ORIGINAL_ID} IN ($placeholders)"
                        val detachedArgs = (listOf(calendarId) + masterIds).toTypedArray()
                        val detachedCursor = contentResolver.query(
                            eventContentUri, detachedProjection,
                            detachedSelection, detachedArgs, null
                        )
                        detachedCursor?.use { c ->
                            val helper2 = DescriptionUrlHelper()
                            while (c.moveToNext()) {
                                val id = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events._ID))
                                val title = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events.TITLE))
                                val storedDescription = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION))
                                val (parsedDescription, parsedUrl) = helper2.splitDescriptionAndUrl(storedDescription)
                                val eventLocation = c.getString(c.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION))
                                val start = c.getLong(c.getColumnIndexOrThrow(CalendarContract.Events.DTSTART))
                                val dtendIdx = c.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                                val end = if (c.isNull(dtendIdx)) start else c.getLong(dtendIdx)
                                val isAllDay = c.getInt(c.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)).toBoolean()
                                val origId = c.getLong(c.getColumnIndexOrThrow(CalendarContract.Events.ORIGINAL_ID))
                                val origTimeIdx = c.getColumnIndexOrThrow(CalendarContract.Events.ORIGINAL_INSTANCE_TIME)
                                val origTime = if (c.isNull(origTimeIdx)) null else c.getLong(origTimeIdx)

                                events.add(
                                    Event(
                                        id = id,
                                        title = title,
                                        startDate = start,
                                        endDate = end,
                                        calendarId = calendarId,
                                        description = parsedDescription,
                                        url = parsedUrl,
                                        location = eventLocation,
                                        isAllDay = isAllDay,
                                        reminders = emptyList(),
                                        attendees = emptyList(),
                                        recurrenceRule = null,
                                        excludedDates = emptyList(),
                                        originalEventId = origId.toString(),
                                        originalInstanceTime = origTime,
                                    )
                                )
                            }
                        }
                    }

                    callback(Result.success(events))

                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }

        }
    }

    override fun deleteEvent(eventId: String, callback: (Result<Unit>) -> Unit) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val calendarId = getCalendarId(eventId)
                    if (isCalendarWritable(calendarId)) {
                        val selection = CalendarContract.Events._ID + " = ?"
                        val selectionArgs = arrayOf(eventId)

                        val deleted = contentResolver.delete(eventContentUri, selection, selectionArgs)
                        if (deleted > 0) {
                            callback(Result.success(Unit))
                        } else {
                            callback(
                                Result.failure(
                                    FlutterError(
                                        code = "NOT_FOUND",
                                        message = "Failed to delete event"
                                    )
                                )
                            )
                        }
                    } else {
                        callback(
                            Result.failure(
                                FlutterError(
                                    code = "NOT_EDITABLE",
                                    message = "Calendar is not writable"
                                )
                            )
                        )
                    }

                } catch (e: FlutterError) {
                    callback(Result.failure(e))

                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun updateEvent(
        eventId: String,
        span: UpdateSpan,
        occurrenceTimeUtcMs: Long?,
        title: String?,
        startDate: Long?,
        endDate: Long?,
        isAllDay: Boolean?,
        description: String?,
        url: String?,
        location: String?,
        reminders: List<Long>?,
        recurrenceRule: String?,
        excludedDates: List<Long>?,
        recurrenceDates: List<Long>?,
        callback: (Result<Event>) -> Unit
    ) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(Result.failure(FlutterError(
                    code = "ACCESS_REFUSED",
                    message = "Calendar access has been refused or has not been given yet"
                )))
                return@requestWritePermission
            }

            // Validate RRULE if a new one was supplied.
            if (!recurrenceRule.isNullOrEmpty()) {
                val v = RecurrenceRuleValidator.validate(recurrenceRule)
                if (v is RecurrenceRuleValidator.Result.Invalid) {
                    callback(Result.failure(FlutterError(
                        code = "INVALID_RRULE",
                        message = "Invalid recurrenceRule",
                        details = v.reason
                    )))
                    return@requestWritePermission
                }
            }

            // Spans that target an occurrence require occurrenceTimeUtcMs.
            if (span != UpdateSpan.ALL_EVENTS && occurrenceTimeUtcMs == null) {
                callback(Result.failure(FlutterError(
                    code = "INVALID_ARGUMENT",
                    message = "occurrenceTimeUtcMs is required for THIS_EVENT / THIS_AND_FUTURE spans"
                )))
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val calendarId = getCalendarId(eventId)
                    if (!isCalendarWritable(calendarId)) {
                        callback(Result.failure(FlutterError(
                            code = "NOT_EDITABLE",
                            message = "Calendar is not writable"
                        )))
                        return@launch
                    }

                    when (span) {
                        UpdateSpan.ALL_EVENTS -> updateMasterRow(
                            eventId = eventId,
                            title = title,
                            startDate = startDate,
                            endDate = endDate,
                            isAllDay = isAllDay,
                            description = description,
                            url = url,
                            location = location,
                            recurrenceRule = recurrenceRule,
                            excludedDates = excludedDates,
                            recurrenceDates = recurrenceDates,
                            callback = callback
                        )
                        UpdateSpan.THIS_EVENT -> insertDetachedChild(
                            masterEventId = eventId,
                            calendarId = calendarId,
                            occurrenceTimeUtcMs = occurrenceTimeUtcMs!!,
                            title = title,
                            startDate = startDate,
                            endDate = endDate,
                            isAllDay = isAllDay,
                            description = description,
                            url = url,
                            location = location,
                            callback = callback
                        )
                        UpdateSpan.THIS_AND_FUTURE -> splitMasterAtOccurrence(
                            masterEventId = eventId,
                            calendarId = calendarId,
                            occurrenceTimeUtcMs = occurrenceTimeUtcMs!!,
                            title = title,
                            startDate = startDate,
                            endDate = endDate,
                            isAllDay = isAllDay,
                            description = description,
                            url = url,
                            location = location,
                            recurrenceRule = recurrenceRule,
                            callback = callback
                        )
                    }
                } catch (e: FlutterError) {
                    callback(Result.failure(e))
                } catch (e: Exception) {
                    callback(Result.failure(FlutterError(
                        code = "GENERIC_ERROR",
                        message = e.message,
                        details = e.cause
                    )))
                }
            }
        }
    }

    /// Span = ALL_EVENTS. ContentResolver.update with only non-null fields.
    private fun updateMasterRow(
        eventId: String,
        title: String?, startDate: Long?, endDate: Long?, isAllDay: Boolean?,
        description: String?, url: String?, location: String?,
        recurrenceRule: String?, excludedDates: List<Long>?,
        recurrenceDates: List<Long>?,
        callback: (Result<Event>) -> Unit
    ) {
        val values = ContentValues()
        if (title != null) values.put(CalendarContract.Events.TITLE, title)
        if (startDate != null) values.put(CalendarContract.Events.DTSTART, startDate)
        if (isAllDay != null) values.put(CalendarContract.Events.ALL_DAY, isAllDay.toInt())
        if (location != null) values.put(CalendarContract.Events.EVENT_LOCATION, location.ifEmpty { null })
        if (description != null || url != null) {
            // Description and URL share storage via DescriptionUrlHelper.
            val helper = DescriptionUrlHelper()
            val merged = helper.mergeDescriptionAndUrl(
                description ?: "",
                url ?: ""
            )
            values.put(CalendarContract.Events.DESCRIPTION, merged?.ifBlank { null })
        }
        if (recurrenceRule != null) {
            if (recurrenceRule.isEmpty()) {
                values.putNull(CalendarContract.Events.RRULE)
            } else {
                values.put(CalendarContract.Events.RRULE, recurrenceRule)
            }
        }
        if (excludedDates != null) {
            if (excludedDates.isEmpty()) {
                values.putNull(CalendarContract.Events.EXDATE)
            } else {
                values.put(
                    CalendarContract.Events.EXDATE,
                    excludedDates.joinToString(",") { formatExdateUtc(it) }
                )
            }
        }
        if (recurrenceDates != null) {
            if (recurrenceDates.isEmpty()) {
                values.putNull(CalendarContract.Events.RDATE)
            } else {
                values.put(
                    CalendarContract.Events.RDATE,
                    recurrenceDates.joinToString(",") { formatExdateUtc(it) }
                )
            }
        }
        // Handle DURATION vs DTEND coupling when start/end change.
        if (startDate != null || endDate != null) {
            // Pull current row to know whether the event is recurring and
            // compute the matching DURATION or DTEND.
            val current = readEventTimingRow(eventId)
            val newStart = startDate ?: current.first
            val newEnd = endDate ?: current.second
            val effectiveRrule = if (recurrenceRule != null) recurrenceRule else current.third
            if (!effectiveRrule.isNullOrEmpty()) {
                val durationSec = (newEnd - newStart) / 1000L
                values.put(CalendarContract.Events.DURATION, "PT${durationSec}S")
                values.putNull(CalendarContract.Events.DTEND)
            } else {
                values.put(CalendarContract.Events.DTEND, newEnd)
                values.putNull(CalendarContract.Events.DURATION)
            }
        }
        val uri = android.content.ContentUris.withAppendedId(eventContentUri, eventId.toLong())
        contentResolver.update(uri, values, null, null)
        retrieveEvent(eventId, callback)
    }

    /// Span = THIS_EVENT. Insert a new row with ORIGINAL_ID + ORIGINAL_INSTANCE_TIME.
    /// The master series stays intact; the new row represents a single detached
    /// occurrence with modified fields.
    private fun insertDetachedChild(
        masterEventId: String,
        calendarId: String,
        occurrenceTimeUtcMs: Long,
        title: String?, startDate: Long?, endDate: Long?, isAllDay: Boolean?,
        description: String?, url: String?, location: String?,
        callback: (Result<Event>) -> Unit
    ) {
        val master = readEventForMutation(masterEventId)
        val newStart = startDate ?: occurrenceTimeUtcMs
        val newEnd = endDate ?: (occurrenceTimeUtcMs + (master.endDate - master.startDate))
        val helper = DescriptionUrlHelper()
        val mergedDescription = helper.mergeDescriptionAndUrl(
            description ?: master.description,
            url ?: master.url
        )?.ifBlank { null }
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.ORIGINAL_ID, masterEventId.toLong())
            put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, occurrenceTimeUtcMs)
            put(CalendarContract.Events.TITLE, title ?: master.title)
            put(CalendarContract.Events.DTSTART, newStart)
            put(CalendarContract.Events.DTEND, newEnd)
            put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
            put(CalendarContract.Events.ALL_DAY, (isAllDay ?: master.isAllDay).toInt())
            put(CalendarContract.Events.DESCRIPTION, mergedDescription)
            put(CalendarContract.Events.EVENT_LOCATION, location ?: master.location)
        }
        val uri = contentResolver.insert(eventContentUri, values)
        val detachedId = uri?.lastPathSegment
            ?: throw FlutterError(code = "GENERIC_ERROR", message = "Failed to insert detached occurrence")
        retrieveEvent(detachedId, callback)
    }

    /// Span = THIS_AND_FUTURE. Terminate the master's RRULE with UNTIL =
    /// occurrenceTime - 1ms; insert a new master starting at occurrenceTime
    /// carrying the same RRULE (or an explicit replacement) plus the
    /// modified fields.
    private fun splitMasterAtOccurrence(
        masterEventId: String,
        calendarId: String,
        occurrenceTimeUtcMs: Long,
        title: String?, startDate: Long?, endDate: Long?, isAllDay: Boolean?,
        description: String?, url: String?, location: String?,
        recurrenceRule: String?,
        callback: (Result<Event>) -> Unit
    ) {
        val master = readEventForMutation(masterEventId)
        val originalRrule = master.recurrenceRule
            ?: throw FlutterError(
                code = "INVALID_ARGUMENT",
                message = "THIS_AND_FUTURE span requires a recurring master"
            )

        // 1. Terminate the master with UNTIL = occurrenceTime - 1ms.
        val untilStr = formatExdateUtc(occurrenceTimeUtcMs - 1)
        val terminatedRrule = withUntil(originalRrule, untilStr)
        val terminateValues = ContentValues().apply {
            put(CalendarContract.Events.RRULE, terminatedRrule)
        }
        val masterUri = android.content.ContentUris.withAppendedId(eventContentUri, masterEventId.toLong())
        contentResolver.update(masterUri, terminateValues, null, null)

        // 2. Insert a new master starting at occurrenceTime.
        val newStart = startDate ?: occurrenceTimeUtcMs
        val newEnd = endDate ?: (occurrenceTimeUtcMs + (master.endDate - master.startDate))
        val newRrule = recurrenceRule ?: originalRrule
        val helper = DescriptionUrlHelper()
        val mergedDescription = helper.mergeDescriptionAndUrl(
            description ?: master.description,
            url ?: master.url
        )?.ifBlank { null }
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title ?: master.title)
            put(CalendarContract.Events.DTSTART, newStart)
            put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
            put(CalendarContract.Events.ALL_DAY, (isAllDay ?: master.isAllDay).toInt())
            put(CalendarContract.Events.DESCRIPTION, mergedDescription)
            put(CalendarContract.Events.EVENT_LOCATION, location ?: master.location)
            val durationSec = (newEnd - newStart) / 1000L
            put(CalendarContract.Events.DURATION, "PT${durationSec}S")
            put(CalendarContract.Events.RRULE, newRrule)
        }
        val uri = contentResolver.insert(eventContentUri, values)
        val newId = uri?.lastPathSegment
            ?: throw FlutterError(code = "GENERIC_ERROR", message = "Failed to insert continuation master")
        retrieveEvent(newId, callback)
    }

    /// Replace any existing UNTIL token in `rrule` with the new value, or
    /// append `UNTIL=<until>` if none was present.
    internal fun withUntil(rrule: String, until: String): String {
        val parts = rrule.split(";")
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.uppercase().startsWith("UNTIL=") }
            .toMutableList()
        // Drop COUNT too — RFC 5545: COUNT and UNTIL are mutually exclusive.
        val filtered = parts.filter { !it.uppercase().startsWith("COUNT=") }
        return (filtered + "UNTIL=$until").joinToString(";")
    }

    /// Internal data class holding the master fields needed for write-time
    /// fallbacks (THIS_EVENT / THIS_AND_FUTURE spans inherit unchanged
    /// fields from the master).
    private data class MutationContext(
        val title: String,
        val description: String?,
        val url: String?,
        val location: String?,
        val startDate: Long,
        val endDate: Long,
        val isAllDay: Boolean,
        val recurrenceRule: String?,
    )

    /// Loads the minimum master fields needed for a span that inherits from
    /// the master (THIS_EVENT, THIS_AND_FUTURE). Throws NOT_FOUND if missing.
    private fun readEventForMutation(eventId: String): MutationContext {
        val projection = arrayOf(
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.RRULE,
            CalendarContract.Events.DURATION,
        )
        val cursor = contentResolver.query(
            eventContentUri, projection,
            "${CalendarContract.Events._ID} = ?", arrayOf(eventId), null
        ) ?: throw FlutterError(code = "NOT_FOUND", message = "Event $eventId not found")
        cursor.use {
            if (!it.moveToNext()) {
                throw FlutterError(code = "NOT_FOUND", message = "Event $eventId not found")
            }
            val title = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.TITLE)) ?: ""
            val storedDescription = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION))
            val (parsedDescription, parsedUrl) = DescriptionUrlHelper().splitDescriptionAndUrl(storedDescription)
            val locationCol = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION))
            val startDate = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Events.DTSTART))
            val rruleIdx = it.getColumnIndexOrThrow(CalendarContract.Events.RRULE)
            val rrule = if (it.isNull(rruleIdx)) null else it.getString(rruleIdx)
            val durationIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DURATION)
            val duration = if (it.isNull(durationIdx)) null else it.getString(durationIdx)
            val endDate = if (rrule != null && duration != null) {
                startDate + parseDurationToMs(duration)
            } else {
                val dtendIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                if (it.isNull(dtendIdx)) startDate else it.getLong(dtendIdx)
            }
            val isAllDay = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)).toBoolean()
            return MutationContext(
                title = title,
                description = parsedDescription,
                url = parsedUrl,
                location = locationCol,
                startDate = startDate,
                endDate = endDate,
                isAllDay = isAllDay,
                recurrenceRule = rrule,
            )
        }
    }

    /// Used by updateMasterRow when only timing fields change: returns
    /// (DTSTART, effectiveEnd, RRULE) so we can decide DURATION vs DTEND.
    private fun readEventTimingRow(eventId: String): Triple<Long, Long, String?> {
        val ctx = readEventForMutation(eventId)
        return Triple(ctx.startDate, ctx.endDate, ctx.recurrenceRule)
    }

    override fun createReminder(reminder: Long, eventId: String, callback: (Result<Event>) -> Unit) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val values = ContentValues().apply {
                        put(CalendarContract.Reminders.EVENT_ID, eventId)
                        put(CalendarContract.Reminders.MINUTES, reminder)
                        put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
                    }
                    contentResolver.insert(remindersContentUri, values)

                    retrieveEvent(eventId, callback)

                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun deleteReminder(reminder: Long, eventId: String, callback: (Result<Event>) -> Unit) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val selection =
                        CalendarContract.Reminders.EVENT_ID + " = ?" + " AND " + CalendarContract.Reminders.MINUTES + " = ?"
                    val selectionArgs = arrayOf(eventId, reminder.toString())

                    val deleted = contentResolver.delete(remindersContentUri, selection, selectionArgs)
                    if (deleted > 0) {
                        retrieveEvent(eventId, callback)
                    } else {
                        callback(
                            Result.failure(
                                FlutterError(
                                    code = "NOT_FOUND",
                                    message = "Failed to delete reminder"
                                )
                            )
                        )
                    }
                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun createAttendee(
        eventId: String,
        name: String,
        email: String,
        role: Long,
        type: Long,
        callback: (Result<Event>) -> Unit
    ) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val values = ContentValues().apply {
                        put(CalendarContract.Attendees.EVENT_ID, eventId)
                        put(CalendarContract.Attendees.ATTENDEE_NAME, name)
                        put(CalendarContract.Attendees.ATTENDEE_EMAIL, email)
                        put(CalendarContract.Attendees.ATTENDEE_RELATIONSHIP, type)
                        put(CalendarContract.Attendees.ATTENDEE_TYPE, role)
                    }
                    contentResolver.insert(attendeesContentUri, values)

                    retrieveEvent(eventId, callback)

                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    override fun deleteAttendee(
        eventId: String,
        email: String,
        callback: (Result<Event>) -> Unit
    ) {
        permissionHandler.requestWritePermission { granted ->
            if (!granted) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "ACCESS_REFUSED",
                            message = "Calendar access has been refused or has not been given yet",
                        )
                    )
                )
                return@requestWritePermission
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val selection =
                        CalendarContract.Attendees.EVENT_ID + " = ?" + " AND " + CalendarContract.Attendees.ATTENDEE_EMAIL + " = ?"
                    val selectionArgs = arrayOf(eventId, email)

                    val deleted = contentResolver.delete(attendeesContentUri, selection, selectionArgs)
                    if (deleted > 0) {
                        retrieveEvent(eventId, callback)
                    } else {
                        callback(
                            Result.failure(
                                FlutterError(
                                    code = "NOT_FOUND",
                                    message = "Failed to delete attendee"
                                )
                            )
                        )
                    }
                } catch (e: Exception) {
                    callback(
                        Result.failure(
                            FlutterError(
                                code = "GENERIC_ERROR",
                                message = e.message,
                                details = e.cause
                            )
                        )
                    )
                }
            }
        }
    }

    // ------------------- Private methods -------------------
    private fun isCalendarWritable(
        calendarId: String,
    ): Boolean {
        val projection = arrayOf(
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL
        )
        val selection = CalendarContract.Calendars._ID + " = ?"
        val selectionArgs = arrayOf(calendarId)

        val cursor = contentResolver.query(calendarContentUri, projection, selection, selectionArgs, null)
        cursor?.use {
            if (it.moveToNext()) {
                val accessLevel = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL))
                return accessLevel >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
            } else {
                throw FlutterError(
                    code = "NOT_FOUND",
                    message = "Failed to retrieve calendar"
                )
            }
        }

        throw FlutterError(
            code = "GENERIC_ERROR",
            message = "An error occurred"
        )
    }

    private fun getCalendarId(
        eventId: String,
    ): String {
        val projection = arrayOf(
            CalendarContract.Events.CALENDAR_ID
        )
        val selection = CalendarContract.Events._ID + " = ?"
        val selectionArgs = arrayOf(eventId)

        val cursor = contentResolver.query(eventContentUri, projection, selection, selectionArgs, null)
        cursor?.use {
            if (it.moveToNext()) {
                return it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.CALENDAR_ID))
            } else {
                throw FlutterError(
                    code = "NOT_FOUND",
                    message = "Failed to retrieve event"
                )
            }
        }

        throw FlutterError(
            code = "GENERIC_ERROR",
            message = "An error occurred"
        )
    }

    private fun retrieveEvent(
        eventId: String,
        callback: (Result<Event>) -> Unit
    ) {
        try {
            val projection = arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DESCRIPTION,
                CalendarContract.Events.EVENT_LOCATION,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.EVENT_TIMEZONE,
                CalendarContract.Events.CALENDAR_ID,
                CalendarContract.Events.ALL_DAY,
                CalendarContract.Events.RRULE,
                CalendarContract.Events.EXDATE,
                CalendarContract.Events.RDATE,
                CalendarContract.Events.DURATION,
            )
            val selection = CalendarContract.Events._ID + " = ?"
            val selectionArgs = arrayOf(eventId)

            val cursor = contentResolver.query(eventContentUri, projection, selection, selectionArgs, null)
            var event: Event? = null

            cursor?.use { it ->
                val descriptionUrlHelper = DescriptionUrlHelper()
                if (it.moveToNext()) {
                    val id = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events._ID))
                    val title = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.TITLE))
                    val storedDescription = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION))
                    val (parsedDescription, parsedUrl) = descriptionUrlHelper.splitDescriptionAndUrl(storedDescription)
                    val eventLocation = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION))
                    val isAllDay = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)).toBoolean()
                    val startDate = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Events.DTSTART))
                    val rruleIdx = it.getColumnIndexOrThrow(CalendarContract.Events.RRULE)
                    val rrule = if (it.isNull(rruleIdx)) null else it.getString(rruleIdx)
                    val exdateIdx = it.getColumnIndexOrThrow(CalendarContract.Events.EXDATE)
                    val exdateRaw = if (it.isNull(exdateIdx)) null else it.getString(exdateIdx)
                    val rdateIdx = it.getColumnIndexOrThrow(CalendarContract.Events.RDATE)
                    val rdateRaw = if (it.isNull(rdateIdx)) null else it.getString(rdateIdx)
                    val durationIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DURATION)
                    val duration = if (it.isNull(durationIdx)) null else it.getString(durationIdx)
                    val endDate = if (rrule != null && duration != null) {
                        startDate + parseDurationToMs(duration)
                    } else {
                        val dtendIdx = it.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
                        if (it.isNull(dtendIdx)) startDate else it.getLong(dtendIdx)
                    }
                    val excludedDates = exdateRaw?.let { parseRfc5545DateList(it) } ?: emptyList()
                    val recurrenceDates = rdateRaw?.let { parseRfc5545DateList(it) } ?: emptyList()
                    val calendarId = it.getString(it.getColumnIndexOrThrow(CalendarContract.Events.CALENDAR_ID))

                    val attendees = mutableListOf<Attendee>()
                    val attendeesLatch = CountDownLatch(1)
                    retrieveAttendees(id) { result ->
                        result.onSuccess {
                            attendees.addAll(it)
                            attendeesLatch.countDown()
                        }
                        result.onFailure { error ->
                            callback(Result.failure(error))
                        }
                    }

                    val reminders = mutableListOf<Long>()
                    val remindersLatch = CountDownLatch(1)
                    retrieveReminders(id) { result ->
                        result.onSuccess {
                            reminders.addAll(it)
                            remindersLatch.countDown()
                        }
                        result.onFailure { error ->
                            callback(Result.failure(error))
                        }
                    }

                    attendeesLatch.await()
                    remindersLatch.await()

                    event = Event(
                        id = id,
                        title = title,
                        startDate = startDate,
                        endDate = endDate,
                        calendarId = calendarId,
                        description = parsedDescription,
                        url = parsedUrl,
                        location = eventLocation,
                        isAllDay = isAllDay,
                        reminders = reminders,
                        attendees = attendees,
                        recurrenceRule = rrule,
                        excludedDates = excludedDates,
                        recurrenceDates = recurrenceDates,
                    )
                }
            }

            if (event == null) {
                callback(
                    Result.failure(
                        FlutterError(
                            code = "NOT_FOUND",
                            message = "Failed to retrieve event"
                        )
                    )
                )
            } else {
                callback(Result.success(event))
            }


        } catch (e: Exception) {
            callback(
                Result.failure(
                    FlutterError(
                        code = "GENERIC_ERROR",
                        message = e.message,
                        details = e.cause
                    )
                )
            )
        }
    }

    private fun retrieveReminders(eventId: String, callback: (Result<List<Long>>) -> Unit) {
        try {
            val reminders = mutableListOf<Long>()
            val projection = arrayOf(
                CalendarContract.Reminders._ID,
                CalendarContract.Reminders.MINUTES,
                CalendarContract.Reminders.METHOD
            )
            val selection = CalendarContract.Reminders.EVENT_ID + " = ?"
            val selectionArgs = arrayOf(eventId)

            val cursor = contentResolver.query(remindersContentUri, projection, selection, selectionArgs, null)
            cursor?.use {
                while (it.moveToNext()) {
                    val minutes = it.getLong(it.getColumnIndexOrThrow(CalendarContract.Reminders.MINUTES))
                    reminders.add(minutes)
                }
            }

            callback(Result.success(reminders))

        } catch (e: Exception) {
            callback(Result.failure(
                FlutterError(
                    code = "GENERIC_ERROR",
                    message = e.message,
                    details = e.cause
                )
            ))
        }
    }

    private fun retrieveAttendees(eventId: String, callback: (Result<List<Attendee>>) -> Unit) {
        try {
            val projection = arrayOf(
                CalendarContract.Attendees.ATTENDEE_NAME,
                CalendarContract.Attendees.ATTENDEE_EMAIL,
                CalendarContract.Attendees.ATTENDEE_RELATIONSHIP,
                CalendarContract.Attendees.ATTENDEE_STATUS,
                CalendarContract.Attendees.ATTENDEE_TYPE,
            )
            val selection = CalendarContract.Attendees.EVENT_ID + " = ?"
            val selectionArgs = arrayOf(eventId)

            val cursor = contentResolver.query(attendeesContentUri, projection, selection, selectionArgs, null)
            val attendees = mutableListOf<Attendee>()

            cursor?.use {
                while (it.moveToNext()) {
                    val name = it.getString(it.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_NAME))
                    val email = it.getString(it.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_EMAIL))
                    val relationship = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_RELATIONSHIP))
                    val type = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_TYPE))
                    val status = it.getInt(it.getColumnIndexOrThrow(CalendarContract.Attendees.ATTENDEE_STATUS))

                    val attendee = Attendee(
                        name = name,
                        email = email,
                        type = relationship.toLong(),
                        role = type.toLong(),
                        status = status.toLong(),
                    )

                    attendees.add(attendee)
                }
            }

            callback(Result.success(attendees))

        } catch (e: Exception) {
            callback(Result.failure(
                FlutterError(
                    code = "GENERIC_ERROR",
                    message = e.message,
                    details = e.cause
                )
            ))
        }
    }

    private fun getSystemAccountLabel(accountType: String): String? {
        val authenticator = accountManager.authenticatorTypes.find { it.type == accountType }

        return authenticator?.let { auth ->
            try {
                packageManager.getText(auth.packageName, auth.labelId, null)?.toString()
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun shareEventAsIcs(
        title: String?,
        startDate: Long?,
        endDate: Long?,
        isAllDay: Boolean?,
        description: String?,
        url: String?,
        location: String?,
        reminders: List<Long>?,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val descriptionUrlHelper = DescriptionUrlHelper()
            val mergedDescription = descriptionUrlHelper.mergeDescriptionAndUrl(description, url)
            val icsContent = icsEventManager.generateIcsContent(
                title = title,
                startDate = startDate,
                endDate = endDate,
                isAllDay = isAllDay,
                description = mergedDescription,
                location = location,
                reminders = reminders
            )

            calendarActivityManager.createShareIntent(icsContent) {
                callback(Result.success(Unit))
            }
        } catch (e: Exception) {
            callback(
                Result.failure(
                    FlutterError(
                        code = "GENERIC_ERROR",
                        message = e.message,
                        details = e.cause
                    )
                )
            )
        }
    }

    // ------------------- RFC 5545 helpers (Phase 1) -------------------

    /**
     * Formats a ms-since-epoch instant as an RFC 5545 UTC date-time:
     *   `20261001T120000Z`
     */
    internal fun formatExdateUtc(ms: Long): String {
        val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        cal.timeInMillis = ms
        val y = cal.get(java.util.Calendar.YEAR)
        val mo = cal.get(java.util.Calendar.MONTH) + 1
        val d = cal.get(java.util.Calendar.DAY_OF_MONTH)
        val h = cal.get(java.util.Calendar.HOUR_OF_DAY)
        val mi = cal.get(java.util.Calendar.MINUTE)
        val s = cal.get(java.util.Calendar.SECOND)
        return "%04d%02d%02dT%02d%02d%02dZ".format(y, mo, d, h, mi, s)
    }

    /**
     * Parses an RFC 5545 EXDATE / RDATE column value (comma-separated UTC
     * times) back into a list of ms-since-epoch instants. Tolerates Apple's
     * date-only floating form (`YYYYMMDD`) per plan-research finding #1.
     */
    internal fun parseRfc5545DateList(raw: String): List<Long> {
        val out = mutableListOf<Long>()
        for (token in raw.split(",")) {
            val t = token.trim()
            if (t.isEmpty()) continue
            val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
            cal.clear()
            when {
                t.length == 8 -> { // YYYYMMDD
                    cal.set(t.substring(0, 4).toInt(), t.substring(4, 6).toInt() - 1, t.substring(6, 8).toInt())
                }
                t.length == 15 || t.length == 16 -> { // YYYYMMDDTHHMMSS or with trailing Z
                    cal.set(
                        t.substring(0, 4).toInt(),
                        t.substring(4, 6).toInt() - 1,
                        t.substring(6, 8).toInt(),
                        t.substring(9, 11).toInt(),
                        t.substring(11, 13).toInt(),
                        t.substring(13, 15).toInt(),
                    )
                }
                else -> continue
            }
            out.add(cal.timeInMillis)
        }
        return out
    }

    /**
     * Parses an ISO 8601 duration as stored in [CalendarContract.Events.DURATION]
     * into milliseconds. Phase 1 supports the seconds form `PT<n>S`, which is
     * what we emit on write. Day form `P<n>D` and week form `P<n>W` are also
     * recognized for round-tripping foreign-written events.
     */
    internal fun parseDurationToMs(raw: String): Long {
        val s = raw.trim().uppercase()
        // PT...S form (seconds): handles "PT3600S", "PT1H30M", "PT45M"
        if (s.startsWith("PT")) {
            var totalSec = 0L
            var num = StringBuilder()
            for (i in 2 until s.length) {
                val ch = s[i]
                when {
                    ch.isDigit() -> num.append(ch)
                    ch == 'H' -> { totalSec += num.toString().toLong() * 3600L; num = StringBuilder() }
                    ch == 'M' -> { totalSec += num.toString().toLong() * 60L; num = StringBuilder() }
                    ch == 'S' -> { totalSec += num.toString().toLong(); num = StringBuilder() }
                }
            }
            return totalSec * 1000L
        }
        // P...D / P...W
        if (s.startsWith("P") && s.endsWith("D")) {
            val days = s.substring(1, s.length - 1).toLong()
            return days * 86_400_000L
        }
        if (s.startsWith("P") && s.endsWith("W")) {
            val weeks = s.substring(1, s.length - 1).toLong()
            return weeks * 7L * 86_400_000L
        }
        return 0L
    }
}

private fun Boolean.toInt() = if (this) 1 else 0

private fun Int.toBoolean() = this != 0
