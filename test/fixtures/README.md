# RRULE Test Corpus

`rrule_corpus.json` is the shared oracle for RFC 5545 RRULE parser tests
across all platforms — iOS (Swift), Android (Kotlin), and Dart.

## Why share via JSON?

EventKit on iOS, `CalendarContract` on Android, and the `rrule` Dart
package all consume the same RFC 5545 RRULE strings, but each platform
has its own quirks. A single JSON oracle lets us verify that the
parser-to-native-representation conversion is consistent everywhere,
using the same set of real-world fixtures.

## Sources

| Source                       | Count | What it covers                                                  |
| ---------------------------- | ----- | --------------------------------------------------------------- |
| `inferred-from-firestore`    | 4     | Real Homzie household patterns reconstructed from production    |
|                              |       | event data (no PII, just title + frequency + start time).       |
| `rfc-5545`                   | 13    | Canonical examples from RFC 5545 §3.8.5.3 — the well-known      |
|                              |       | parser smoke tests, including positional `BYDAY` and `BYSETPOS`. |
| `gcal-or-apple`              | 7     | What Google Calendar and Apple Calendar actually emit when a    |
|                              |       | user picks a recurrence option in the UI.                       |
| `edge-case`                  | 5     | DST boundary, leap-year Feb-29, `WKST`, `BYMONTHDAY=31`,        |
|                              |       | far-future `UNTIL`, Apple's floating `UNTIL` (no `Z`).          |

## Schema

```jsonc
{
  "id":          "unique stable identifier (use in test names)",
  "source":      "inferred-from-firestore | rfc-5545 | gcal-or-apple | edge-case",
  "title":       "human-readable label",
  "description": "what this fixture exercises",
  "dtstart_utc": "RFC 3339 timestamp (timezone-aware)",
  "duration_minutes": 60,
  "all_day":     false,
  "rrule":       "the RRULE value, WITHOUT the 'RRULE:' prefix",
  "expected_first_occurrences": [
    "2026-09-02T09:00:00+00:00",
    "2026-09-09T09:00:00+00:00"
    // ... up to 8 entries within test_window
  ],
  "notes":       ""
}
```

### `expected_first_occurrences` semantics

This is the **oracle** for integration tests. Any conformant
RRULE expander, given `dtstart_utc` and `rrule`, must produce
exactly these dates within the test window (`2026-05-01` →
`2027-12-31`).

If `expected_first_occurrences` is an object `{"_parser_note": "..."}`
instead of an array, that fixture documents a known parser disagreement
(e.g. `dateutil` rejects Apple's floating `UNTIL`). Such cases describe
exactly the kind of robustness we want eventide to deliver.

## Adding real RRULEs from a user's calendar

The `inferred-from-firestore` entries are *reconstructed* from observed
occurrence patterns — they're plausible but not guaranteed to match the
source calendar's actual RRULE byte-for-byte. To get the real strings:

1. Ask the user for the **secret iCal URL** from their Google Calendar
   settings ("Geheime Adresse im iCal-Format" / "Secret address in iCal
   format"). This is a public-by-token URL that returns RFC 5545 `.ics`.
2. `curl` it down, grep for `RRULE:` lines, augment the corpus.

The user does **not** need to grant OAuth or share their account — the
iCal URL is a feed token they can revoke at any time.

## Consumers

- **iOS**: `example/ios/EventideTests/RecurrenceRuleParserTests.swift`
  asserts on the parsed `EKRecurrenceRule` structure (property-level).
- **Android**: not yet wired.
- **Dart**: not yet wired (we have the `rrule` package as a dep on the
  Homzie side already).
