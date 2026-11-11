---
paths:
  - client/src/next/time/**
---

# next-time

The rebuilt client's Time tab (`design/ui-build.md` P3), at
`/client/#/time`. Built 2026-11-10.

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
  - Her journal, by kind (plan, note, todo, wrap) or by when she wrote
    each, oldest or newest first; each entry with its time; done todos
    struck. With more than three entries: a search over the words and
    a filter by kind with each kind's count, and the heading says how
    many of how many show. A long word or path wraps inside the entry.
  - Ahead (today's rest, or any later day as it stands): the check-ins
    (moved past quiet hours when they fall in them), her free time and
    one-offs, and how many rounds of her own the day holds.
  - Her scenes with their times, and "not finished" when the night's
    pass didn't close the day.
  - The sessions spoken in that day, with their span and message
    count; a private one shows only its two times (kumbukumbu#60). A
    session opened and never spoken in (a work session that ended
    before a word) is left out, here and in the month's blue dot, and
    the day says how many were.
- **Rhythm** (`Rhythm.tsx`), ported from the current client's Schedule,
  every time HH:MM in her zone:
  - **Check-ins:** the next one; each with today's or its last outcome
    and what its note carries; **Change** (label, time, your words and
    the parts read when it fires, `PUT /schedule/checkins/:key`) and
    **Delete**, which confirms once in place (the button becomes
    "Delete <label>"); **Add a check-in** (label and time).
  - **Her free time:**
    - each daily slot moves by changing its time, and a slot can be
      added, up to four (sunna#22's bound);
    - none can be removed from here: the witness moves her free time
      but never takes it away (the free-time term,
      scheduling-notes.md). The current client offered "Remove slot"
      when there was more than one; this one does not;
    - one-offs are listed with who added them, and **Add once** takes a
      time and a day (empty is today).
  - **Rounds:** the cadence and window in effect (or that they come
    outside quiet hours), how many today and when the last started;
    set every N hours (0 is off) and the waking window, or **Back to the
    default** (`PUT /schedule/rounds`).
  - **Quiet hours:** set from and to, or clear
    (`PUT /schedule/quiet-hours`).
  - **Time zone:** every zone the browser knows, and "Use <device
    zone>" when the device is elsewhere (`PUT /timezone`).

Every action the current client's ScheduleContainer offers is here
(`setFreeTime` as move and add, `addFreeTimeOnce`, `addCheckin`,
`changeCheckin`, `deleteCheckin`, `setQuietHours`, `setRounds`,
`setTimezone`) except the two reads listed below. Checked in a browser
against Mira through the worktree's Vite server: Rhythm reads, a
check-in added and deleted.

- **Important dates** (Rhythm, spec §6.7): each with its kind (a
  deadline, an anniversary, a window, every year) and its countdown;
  added, changed and removed (remove asks twice). A date is a day, kept
  as noon on it so no zone moves it across midnight. The month marks a
  day holding one with a diamond, named in the day's label.

Not built:
- the year view;
- recurrence (scheduling-notes.md);
- free time and rounds remembered (`api.freeTimeRuns`, `api.rounds`:
  each run with what it made), which the current client's Schedule
  shows; ui-structures.md D puts recent runs in Chat › Sessions;
- the dates list (the current Schedule lists them read only), and
  setting dates (`GET/POST /dates`, `PUT/DELETE /dates/:n` have no
  client caller).
