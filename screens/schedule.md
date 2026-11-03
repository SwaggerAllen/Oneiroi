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

## #1 Shows

Today in the resident's zone: last and next check-in, today's events; the day's check-ins, digest and free time with last firings; quiet hours; nightly and weekly jobs.

## #2 Does

Add, change, delete a check-in; set times and quiet hours; pause the resident.

Built: free time's slots moved as a whole list (sunna #22: one to four,
never none, so a list of one has no remove button); a check-in added or
deleted (the delete confirms in place); quiet hours set or cleared; the
dates listed with their countdowns; the resident's time zone, which
every time here is read in, set from a list or, when this device is
elsewhere, in one tap (`PUT /v1/residents/:id/timezone`; Lily's stayed
UTC until 2026-11-03, and her free time ran at 6:30 and 14:30 Pacific).
Times are chosen by hour and minute (`TimeField`), never an
`<input type="time">`: on an iPhone a cleared one looks set while it is
empty, and the second check-in could not be added. Not built yet: changing a check-in's
label or time in place (the route exists, `PUT .../checkins/:key`),
adding or changing a date here, and pausing the resident, which has no
route of its own on this screen.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
