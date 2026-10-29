---
paths:
  - lib/oneiroi/sunna/**
  - lib/oneiroi/sunna.ex
  - lib/oneiroi_web/controllers/schedule_controller.ex
  - priv/prompts/checkin.md
  - priv/prompts/free_time.md
  - priv/repo/migrations/*_sunna.exs
---

# sunna

**Schedule.** Old Norse, SOON-nah.

> "Mundilferi is he who begat the moon, / And fathered the flaming sun; / The round of heaven each day they run, / To tell the time for men." — Poetic Edda, Vafþrúðnismál 23, trans. H. A. Bellows (1923)

Sunna is the sun itself personified — daughter of Mundilfari, sister of the moon — driving her chariot around the heavens every day without fail, the wolf Sköll always at her heels. The myth is honest about the round: the wolf is chasing. And when the sun is finally taken, her daughter takes up the road (Vafþrúðnismál 47).

The schedule subsystem — check-ins, the morning digest, the nightly free time — is named for the daily round: the one appointment that has never once been missed. Deadlines chase everything else, as the wolf chases her; and every schedule hands off to its successor, as hers does.

Check-ins, free time, quiet hours, important dates and the journal's
day row, per resident, in the resident's zone. Spec §6.7. Built in P2
(slice 1) under `Oneiroi.Sunna`, the system's name rather than the
spec's `schedule/`, as Eunomia is; the digest's time and the nightly
and weekly jobs arrive with the systems that run them.

## #1 Owns

`lib/oneiroi/sunna/**` and `lib/oneiroi/sunna.ex`: the `schedule-<resident_id>` stream (`Schedule`, `Commands`, `Events`, `Router`), the projections (`Store`, `Projectors.Schedules`), the service (`Schedules`), the minute tick (`TickWorker`), the wake port (`Wake`); the two prompt files the wakes carry; the schedule controller; the resident's `timezone` column, written by Agathos Daimon (agathos-daimon #17) and read here.

## #2 Standing decisions

Carried from spec §6.7; the reason for each is there.

- **#3 Oban-driven, per resident, in the resident's timezone; a check-in fires once a day whatever restarts, late within 15 minutes and otherwise missed.**
- **#4 Quiet hours are the steward's; a wake queued inside them is deferred to their end and the screen says so in words.**
- **#5 Suspended residents schedule nothing; a wake resumes the beat.**
- **#8 Dates are rows and a countdown is never written (spec §6.7, F56).** A `date` row with its kind and instant, citeable and taggable; "days to" is derived on the turn that reads it, never copied into prose.
- **#9 The journal's day row is created here, at the day's first check-in (spec §6.5).** A day the resident never wrote is a row with a plan and nothing else, visible, rather than an absent file.

Decided in the build:

- **#10 Times of day are the resident's, and the zone is a dependency.** A check-in is `HH:MM` and a day is an ISO date, both in the zone on the resident's row (`Etc/UTC` until the steward sets one); every instant is shifted into it with `DateTime.shift_zone!/2` over the `tz` database (`config :elixir, :time_zone_database`), and an ambiguous local time takes its first reading, a gap the instant after it. A zone the database does not know is refused at the command edge.
- **#11 The tick is a cross-tenant job under the platform scope, named here.** `TickWorker` runs every minute from this system's `oban_queues/0`; it reads the roster of residents with something scheduled in a platform-scoped transaction of its own, then takes each resident's scope in turn. The roster read is a transaction and not the worker's process scope alone, because the process scope passes the repo's check and sets nothing on the connection, so the policy answers no rows and the tick does nothing, quietly.
- **#12 The wake is a port.** `Oneiroi.Sunna.Wake` is the one callback a check-in or free time calls, with the core's note and the purpose the answer bills under; the implementation is named in `SUNNA_WAKE` (brain, the in-core loop, in every build so far) and read at the call. A port rather than a call because the brain reads this system's dates on every turn and the schedule wakes the brain: a direct call each way is the cycle Boundary and the cycles gate both reject. Gjallarhorn (the wake fan-out, P3) takes this port over when hands arrive.
- **#13 A firing is an event before the wake, and a day's outcome is one of four.** `CheckinFired`, `CheckinMissed` or `WakeDeferred{until}` per check-in per day, recorded ahead of any wake, so a restart between the two fires nothing twice and a tick that runs twice in a minute is one event. A deferred wake fires at its end; a fired or missed one is final for the day. A check-in set or changed after its time today carries the day it was set on and waits for tomorrow, so a new 06:00 set at 08:00 is not "missed" on a day it was never due.
- **#14 Free time is a session of its own kind on its own budget line, once a day.** At its time the tick opens a `free_time` session with the steward as its only party, wakes the brain on `priv/prompts/free_time.md` under the `free_time` purpose, and records `FreeTimeRan{session_key}` or `FreeTimeFailed{reason}` for the day; a failure is said on the schedule and not retried until tomorrow.
- **#15 The dates are a section the brain reads, derived on that read.** `dates_text/1` renders every date with its countdown counted in the resident's zone now; the brain injects it as `dates` on every turn (brain #17) and the check-in note carries the same text, so the resident is told "10 days to the interview" by the row and never by a file.
- **#16 The late window is a bound.** `SUNNA_LATE_MINUTES` is spec §6.7's fifteen minutes, carried from David and not measured here; the tick fires inside it and misses past it, for check-ins and free time alike.

## #6 Initial vs target

Initial (P2, slice 1): check-ins, quiet hours, free time, dates and the
day row over the API, with the tick and the wake into the main session.
Target: the digest's time once inbound lands, the nightly and weekly
jobs as their systems arrive, the Schedule screen (`screens/schedule.md`).

## #7 Depends on

The platform; Agathos Daimon for the resident's row, its state and its
zone; memory for sessions; the ledger's prompt files; the brain through
the wake port, never directly.
