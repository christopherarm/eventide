package sncf.connect.tech.eventide

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Pure unit tests for [RecurrenceRuleValidator]. No Android deps, runs as plain JVM JUnit.
 * Covers the Phase 1 validation rules plus a few Phase 2 features we explicitly allow
 * to pass through (Android stores RRULE verbatim).
 */
class RecurrenceRuleValidatorTest {

    // MARK: - Accepts valid RRULEs

    @Test
    fun `accepts FREQ DAILY`() {
        assertOk("FREQ=DAILY")
    }

    @Test
    fun `accepts FREQ WEEKLY with BYDAY`() {
        assertOk("FREQ=WEEKLY;BYDAY=MO,WE,FR")
    }

    @Test
    fun `accepts FREQ MONTHLY with BYMONTHDAY and COUNT`() {
        assertOk("FREQ=MONTHLY;BYMONTHDAY=15;COUNT=12")
    }

    @Test
    fun `accepts FREQ YEARLY with UNTIL`() {
        assertOk("FREQ=YEARLY;UNTIL=20271231T235959Z")
    }

    @Test
    fun `accepts positional BYDAY (Phase 2 stored verbatim)`() {
        // Android stores the RRULE string as-is; the iOS parser is the one
        // that rejects positional BYDAY. Validator is intentionally lenient.
        assertOk("FREQ=MONTHLY;BYDAY=1FR")
    }

    @Test
    fun `accepts positional BYDAY with negative offset (Phase 2A)`() {
        // Apple emits BYDAY=-1FR for "monthly on the last Friday".
        assertOk("FREQ=MONTHLY;BYDAY=-1FR")
    }

    @Test
    fun `accepts positional BYDAY in yearly context (Phase 2A)`() {
        // Thanksgiving: yearly on the last Thursday of November.
        assertOk("FREQ=YEARLY;BYDAY=-1TH;BYMONTH=11")
    }

    @Test
    fun `accepts multi-positional BYDAY (Phase 2A)`() {
        // First Monday OR last Friday of each month — RFC-legal, rare.
        assertOk("FREQ=MONTHLY;BYDAY=1MO,-1FR")
    }

    @Test
    fun `accepts BYSETPOS (Phase 2 stored verbatim)`() {
        assertOk("FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")
    }

    @Test
    fun `accepts BYSETPOS with positive value (Phase 2B)`() {
        // Outlook export: 3rd Tue/Wed/Thu of the month.
        assertOk("FREQ=MONTHLY;COUNT=3;BYDAY=TU,WE,TH;BYSETPOS=3")
    }

    @Test
    fun `accepts WKST (Phase 2 stored verbatim)`() {
        assertOk("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,SU;WKST=SU")
    }

    @Test
    fun `accepts WKST with UNTIL (Phase 2C)`() {
        // Google emits WKST=SU on weekly multi-day rules.
        assertOk("FREQ=WEEKLY;UNTIL=20261007T000000Z;WKST=SU;BYDAY=TU,TH")
    }

    @Test
    fun `accepts Apple floating UNTIL (no Z suffix)`() {
        // Apple's all-day events emit UNTIL without Z. We accept on round-trip
        // even though it's technically non-standard for non-all-day rules.
        assertOk("FREQ=WEEKLY;UNTIL=20261001;BYDAY=MO")
    }

    // MARK: - Rejects invalid RRULEs

    @Test
    fun `rejects empty string`() {
        assertInvalid("", "Empty RRULE")
    }

    @Test
    fun `rejects whitespace-only`() {
        assertInvalid("   ", "Empty RRULE")
    }

    @Test
    fun `rejects missing FREQ`() {
        assertInvalid("INTERVAL=2;BYDAY=MO", "FREQ is required")
    }

    @Test
    fun `rejects unknown FREQ value`() {
        assertInvalid("FREQ=NANOSECONDLY", "Unknown FREQ value")
    }

    @Test
    fun `rejects malformed segment without equals`() {
        assertInvalid("FREQ=WEEKLY;BYDAY", "Malformed segment")
    }

    @Test
    fun `rejects malformed segment with leading equals`() {
        assertInvalid("FREQ=WEEKLY;=foo", "Malformed segment")
    }

    @Test
    fun `rejects malformed segment with trailing equals`() {
        assertInvalid("FREQ=WEEKLY;BYDAY=", "Malformed segment")
    }

    @Test
    fun `rejects duplicate keys`() {
        assertInvalid("FREQ=WEEKLY;BYDAY=MO;BYDAY=TU", "Duplicate key")
    }

    @Test
    fun `rejects COUNT and UNTIL together`() {
        assertInvalid(
            "FREQ=DAILY;COUNT=5;UNTIL=20261231T235959Z",
            "COUNT and UNTIL are mutually exclusive"
        )
    }

    @Test
    fun `rejects negative COUNT`() {
        assertInvalid("FREQ=DAILY;COUNT=-5", "COUNT must be a positive integer")
    }

    @Test
    fun `rejects zero COUNT`() {
        assertInvalid("FREQ=DAILY;COUNT=0", "COUNT must be a positive integer")
    }

    @Test
    fun `rejects non-numeric INTERVAL`() {
        assertInvalid("FREQ=DAILY;INTERVAL=many", "INTERVAL must be a positive integer")
    }

    @Test
    fun `rejects zero INTERVAL`() {
        assertInvalid("FREQ=DAILY;INTERVAL=0", "INTERVAL must be a positive integer")
    }

    // MARK: - Helpers

    private fun assertOk(rrule: String) {
        val r = RecurrenceRuleValidator.validate(rrule)
        assertTrue(
            r is RecurrenceRuleValidator.Result.Ok,
            "Expected Ok for '$rrule', got $r"
        )
    }

    private fun assertInvalid(rrule: String, reasonContains: String) {
        val r = RecurrenceRuleValidator.validate(rrule)
        when (r) {
            is RecurrenceRuleValidator.Result.Invalid ->
                assertTrue(
                    r.reason.contains(reasonContains),
                    "Expected reason to contain '$reasonContains', got: '${r.reason}'"
                )
            else -> throw AssertionError("Expected Invalid for '$rrule', got Ok")
        }
    }
}
