---
paths:
  - client/src/next/time/**
---

# next-time

The rebuilt client's Time tab (`design/ui-build.md` P3), at
`/client/next.html#/time`. Built 2026-11-10.

- **Calendar | Rhythm,** both mounted.
- **The month:**
  - Sunday first, arrows across months and years.
  - Today in the witness's colour.
  - Past days are raised. Under each date, from one read of the month
    (`GET …/days`, sunna#48): a lilac dot if she wrote in her journal, a
    blue dot if a session was spoken in that day, a bar for her scenes
    (longer with more), and a ring for free time ahead.
  - A day opens as `day/YYYY-MM-DD` on this tab's stack.
- **A day:**
  - Her journal, in order: plan, note, todo, wrap; done todos struck.
  - Ahead (today's rest, or any later day as it stands): the check-ins
    (moved past quiet hours when they fall in them), her free time and
    one-offs, and how many rounds of her own the day holds.
  - Her scenes with their times, and "not finished" when the night's
    pass didn't close the day.
  - The sessions spoken in that day, with their span and message
    count; a private one shows only its two times (kumbukumbu#60).
- **Rhythm:**
  - Check-ins.
  - Her free time:
    - each daily slot can be moved by changing its time, and a slot can
      be added;
    - none can be removed from here: the witness moves her free time
      but never takes it away (the free-time term, scheduling-notes.md);
    - one-offs are listed.
  - Rounds, quiet hours and the time zone, read-only.

Not built:
- the year view;
- editing check-ins, rounds and quiet hours (the current client still
  does those);
- recurrence (scheduling-notes.md).
