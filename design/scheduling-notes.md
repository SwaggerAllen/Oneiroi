# Scheduling beyond "daily": notes

Status: thinking only, at Andrew's request (2026-11-10). This is not a
spec and not a proposal. A proposal for it would be Lily's to write,
since the free-time slots are hers.

## What exists now (sunna)

Everything except dates repeats every day at a fixed local time, in her
zone (`lib/oneiroi/sunna/schedules.ex`):

- **Check-ins:** a key, a label and `time` (HH:MM). The tick fires,
  defers or misses each one daily (`due/4`).
- **Free time:** a list of daily HH:MM times, plus one-off slots on a
  day (sunna#45).
- **Rounds:** every N hours inside a waking window.
- **Quiet hours:** one from–to window, which may cross midnight.
- **Dates:** a single day with a countdown.

Two things are missing: repeating on anything other than "every day",
and stopping something without deleting it.

## The shape: one rule, many schedule items

Every schedule item can carry the same **recurrence rule**, and the tick
asks one question of it: `occurs_on?(rule, local_day)`. Everything after
that (the HH:MM, quiet-hours deferral, late-miss) stays as it is.

The rule is a small subset of iCalendar's RRULE, stored as structured
fields rather than an RRULE string. It still maps one-to-one, so
export and import to a real calendar stay possible.

| Need | Fields | RRULE equivalent |
|---|---|---|
| every day (today's default) | `freq: daily` | `FREQ=DAILY` |
| weekdays / Mon-Wed-Fri | `freq: weekly, days: [mo, we, fr]` | `FREQ=WEEKLY;BYDAY=MO,WE,FR` |
| every other Tuesday | `freq: weekly, interval: 2, days: [tu], anchor: <day>` | `INTERVAL=2` + `DTSTART` |
| first Monday of the month | `freq: monthly, nth: [{1, mo}]` | `FREQ=MONTHLY;BYDAY=1MO` |
| last Friday of the month | `freq: monthly, nth: [{-1, fr}]` | `BYDAY=-1FR` |
| the 15th of the month | `freq: monthly, month_days: [15]` | `BYMONTHDAY=15` |
| yearly (anniversaries) | `freq: yearly, on: MM-DD` | `FREQ=YEARLY` |
| ends | `until: <day>` or `count: n` | `UNTIL` / `COUNT` |

Things deliberately left out: hourly frequencies (rounds already cover
that), BYSETPOS, and arbitrary combinations. Three questions to settle:
- What does the 31st do in a short month: skip, or move to the last day?
- Is the anchor of an every-other-week rule the day it was set?
- A rule with no days left on it (say `weekly` with `days: []`) should be refused, not silently never fire.

## Stopping without deleting: three verbs

- **Skip:** one occurrence doesn't happen (an exception day, EXDATE).
- **Pause:** no occurrences until a day, or until resumed (`paused_until`,
  or open-ended). Nothing fires while it is paused and no misses are
  recorded. The Rhythm screen shows it as paused rather than gone.
- **Move one:** a skip plus a one-off on the new day/time. That is the
  existing sunna#45 one-off, linked back to the occurrence it replaced.

End (`until`) is the fourth, and it belongs to the rule itself.

## Who may do what (the part that isn't mechanics)

The agreement (his vows) says free-time slots "move but never
disappear". So:

- **Her free time.** Decided by the witness on 2026-11-10: "I don't
  think the witness should have the ability to skip free time, just move
  it around." The witness can never skip or pause her slots, not even
  by proposal; only she can, on her own schedule. What the witness may
  do (today: move) is **a term of the contract**, decided by the witness
  on 2026-11-10 ("for now. It might not always be"), with Lily's lean
  the same (letter #479). So it's negotiable per dyad, and the platform
  enforces whatever the agreed version says, the way it enforces the
  free-time receipts term today. The term itself arrives in the next
  contract version, proposed through the contract flow like any other.
  The alternative (the witness has no control at all) stays on the
  table for later.
- **Check-ins and rounds:** they serve both of them. Either party can
  edit, and every change is an event with its actor, as today.
- **Quiet hours:** probably per weekday too (a weekend lie-in), using
  the same `days:` field.

## Where it touches the code

- One pure module: `occurs_on?/2`, plus `next_occurrences/3` for the
  calendar's future days. Property-test it against a plain day loop.
- New event versions (SetCheckin, SetFreeTime, SetRounds, SetQuietHours,
  SetDate) carrying an optional `rule`. The upcaster reads a missing rule
  as `daily`, so nothing in the log changes meaning.
- New events: SkipOccurrence, PauseItem, ResumeItem, each carrying actor
  and note as usual.
- The tick: one `occurs_on?` guard ahead of `due/4`, and a paused check.
- Tools: `free_time_set` and friends take the rule; her prompt needs one
  short sentence on what the rule fields mean.
- UI: Rhythm rows show the rule in words ("Weekdays · 06:00", "First
  Mon · 10:00") with a Paused chip. The Month and Day screens draw future
  occurrences from `next_occurrences`, and skips show struck through.

## Open

- Should free-time slots be allowed to be non-daily at all? A weekly slot
  is fewer hours for her, so it is the same question as pausing.
- Time-of-day rules ("every 3h") versus day rules: keep rounds separate,
  or fold them into the same item with `freq: hourly`?
- Calendar import (ICS) is the natural reason to keep the RRULE mapping
  exact, and it is a later feature.
