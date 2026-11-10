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
  - Past days are raised, and a lilac dot marks each day she wrote in
    her journal.
  - A day opens as `day/YYYY-MM-DD` on this tab's stack.
- **A day:**
  - Her journal, in order: plan, note, todo, wrap; done todos struck.
  - On today: the check-ins and free time still to come.
  - The day's sessions.
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
- scene and session marks on the month, and future days' computed
  schedules (S5, calendar ranges);
- the year view;
- editing check-ins, rounds and quiet hours (the current client still
  does those);
- recurrence (scheduling-notes.md).
