---
paths:
  - client/src/screens/schedule/**
---

# schedule

Schedule (spec §10), built 2026-11-02: `client/src/screens/schedule/`
(`Schedule.tsx`, its stories and tests), reached from the bottom nav and
loaded by `ScheduleContainer` in `client/src/app/App.tsx` from
`GET /v1/residents/:id/schedule`. The state list lives in the stories
(DESIGN §4); nothing here names a state.

Built: the top bar names the day and the zone every time is read in.
**Time zone**: the resident's zone, set from every zone the browser
knows or, when this device is elsewhere, in one tap ("Use <zone>")
(`PUT /v1/residents/:id/timezone`; Lily's stayed UTC until 2026-11-03,
and her free time ran at 6:30 and 14:30 Pacific). **Free time**: under it, **One-off** (sunna#45): the one-off slots ahead, each with its day and who added it, and a form, At (hour and minute) and On (a date, empty for today), Add once (`POST .../schedule/free-time/once`); one-offs never change the daily list. Then each
slot with what it did today, moved as a whole list
(`PUT .../schedule/free-time`; sunna#22: one to four, never none, so a
list of one has no remove button and a fifth cannot be added, said as
a bound). **Free time, remembered** (brain#53, sunna#25): the latest
runs from `GET .../schedule/free-time`, newest first, each with its day
and slot, ran or failed with the reason, its turns, and the receipts of
what it made as a short list in the platform's words ("nothing
written" when it made nothing); free time is private as to its words,
so nothing here opens its conversation. Read with the schedule and
again on coming back to the page; while it has not come the section is
not shown. **Rounds, remembered** (sunna#39): the latest rounds from
`GET .../schedule/rounds`, the same list's shape: each with its day and
drawn time, started (running, or stopped before it was recorded), ran
or failed with the kind, its turns, and what left it in the platform's
words ("nothing left it" when nothing did). **Check-ins**: the next one, each with today's outcome or its
last, added by label and time (`POST .../schedule/checkins`) or deleted
(`DELETE .../checkins/:key`, confirming in place). Each says what its note carries ("Carries: your words, Dates, Today's plan"), and "Edit the note" opens, in place, a box for the witness's own words and a checkbox for each part of the server's catalog with what it reads; saving sends the parts in the catalog's order and the words (`PUT .../checkins/:key`, sunna#28). **Rounds** (sunna#30): whether they are on, every how many hours and between what times (or outside quiet hours when those are set), each marked when it is the default, how many today and when the last one started, with "What happens in a round isn't shown here"; a form for the hours (0 is off) and the window, and "Back to the default" when either is her own (`PUT .../schedule/rounds`). The work queue moved to its own screen (sunna#38, `screens/more.md`). **Quiet hours**: set
or cleared (`PUT .../schedule/quiet-hours`). **Dates**: listed with
their kind and countdown. Every time is chosen by hour and minute
(`TimeField`, two selects, minutes in fives with a saved minute off
the step kept as its own option), never an `<input type="time">`: on
an iPhone a cleared one looks set while it is empty, and the second
check-in could not be added. Not built: the last check-in and today's
events, the digest, nightly and weekly jobs, changing a check-in's
label or time in place (the route exists, `PUT .../checkins/:key`, and
the note editor uses it, but nothing on the screen edits label or time), adding
or changing a date here, and pausing the resident, which has no route
of its own on this screen.

## #1 Shows

Today in the resident's zone: last and next check-in, today's events; the day's check-ins, digest and free time with last firings; quiet hours; nightly and weekly jobs.

## #2 Does

Add, change, delete a check-in; set times and quiet hours; pause the resident.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
