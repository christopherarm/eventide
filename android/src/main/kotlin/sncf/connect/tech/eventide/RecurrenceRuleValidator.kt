package sncf.connect.tech.eventide

/**
 * Lightweight syntactic validator for RFC 5545 RRULE strings before they are
 * persisted into [android.provider.CalendarContract.Events.RRULE].
 *
 * Phase 1 scope mirrors the iOS RecurrenceRuleParser:
 *   - Accepts: FREQ, INTERVAL, COUNT, UNTIL, BYDAY (non-positional),
 *              BYMONTHDAY, BYMONTH.
 *   - Rejects: malformed segments, duplicate keys, COUNT+UNTIL conflict,
 *              unknown FREQ values.
 *
 * Android stores the RRULE string verbatim (no parsing on read), so we
 * intentionally do not normalize values here. We only reject inputs that
 * the CalendarProvider would silently misbehave on or that violate RFC
 * §3.3.10 (COUNT/UNTIL mutual exclusion).
 *
 * Phase 2 features (positional BYDAY `1MO`/`-1FR`, BYSETPOS, WKST, RDATE,
 * EXRULE, BYWEEKNO, BYYEARDAY, sub-daily FREQ) are NOT rejected here.
 * Android happily round-trips them through the RRULE column; the limit
 * is on the iOS parser side.
 */
object RecurrenceRuleValidator {

    private val ALLOWED_FREQ = setOf(
        "DAILY", "WEEKLY", "MONTHLY", "YEARLY",
        "SECONDLY", "MINUTELY", "HOURLY",
    )

    sealed class Result {
        object Ok : Result()
        data class Invalid(val reason: String) : Result()
    }

    fun validate(rrule: String): Result {
        if (rrule.isBlank()) return Result.Invalid("Empty RRULE")

        val parts = mutableMapOf<String, String>()
        for (segment in rrule.split(";")) {
            val trimmed = segment.trim()
            if (trimmed.isEmpty()) continue
            val eq = trimmed.indexOf('=')
            if (eq <= 0 || eq == trimmed.length - 1) {
                return Result.Invalid("Malformed segment: $trimmed")
            }
            val key = trimmed.substring(0, eq).uppercase()
            val value = trimmed.substring(eq + 1)
            if (parts.containsKey(key)) {
                return Result.Invalid("Duplicate key: $key")
            }
            parts[key] = value
        }

        val freq = parts["FREQ"] ?: return Result.Invalid("FREQ is required")
        if (freq.uppercase() !in ALLOWED_FREQ) {
            return Result.Invalid("Unknown FREQ value: $freq")
        }

        if (parts.containsKey("COUNT") && parts.containsKey("UNTIL")) {
            return Result.Invalid("COUNT and UNTIL are mutually exclusive (RFC 5545 §3.3.10)")
        }

        parts["COUNT"]?.let { v ->
            val n = v.toIntOrNull()
            if (n == null || n <= 0) {
                return Result.Invalid("COUNT must be a positive integer (got: $v)")
            }
        }

        parts["INTERVAL"]?.let { v ->
            val n = v.toIntOrNull()
            if (n == null || n <= 0) {
                return Result.Invalid("INTERVAL must be a positive integer (got: $v)")
            }
        }

        return Result.Ok
    }
}
