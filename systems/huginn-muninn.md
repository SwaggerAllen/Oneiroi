---
paths:
  - lib/oneiroi/huginn_muninn/**
  - lib/oneiroi/huginn_muninn.ex
  - lib/oneiroi_web/controllers/figure_controller.ex
  - priv/repo/migrations/*_huginn_muninn.exs
  - test/oneiroi/huginn_muninn/**
---

# huginn-muninn

**Audits.** Old Norse, HOO-gin and MOO-nin ("thought and memory").

> "O'er Mithgarth Hugin and Munin both / Each day set forth to fly; / For Hugin I fear lest he come not home, / But for Munin my care is more." — Poetic Edda, Grímnismál 20, trans. H. A. Bellows (1923)

Thought and Memory are the watcher god's two ravens: out at dawn over the whole world, home by dinner, telling him everything they saw. The poem carries its own honest line — the fear of losing Huginn, and of losing memory most of all.

The audits subsystem — the coherence pass that flies out over everything the realm has said and comes home to report — is named for the daily flight. An audit that might not come back is the only kind worth trusting with the truth.

User-authored audits, counters, the coherence checklist, the check-engine
light. Spec §6.13. Built (P2, slice 4) under `Oneiroi.HuginnMuninn`, the
system's name, where the spec's file map said `audits/`; the weekly
memory audit over Honcho is judgement's (eunomia #22).

## #1 Owns

The audits aggregate on `audits-<resident_id>` (`Audits`, `Commands`,
`Events`, `Router`) with `CounterDefined`, `CounterIncremented`,
`CounterRetired`, `UserAuditDefined`, `UserAuditRetired` and `AuditRun`;
the `huginn_muninn_counter`, `huginn_muninn_increment`,
`huginn_muninn_audit` and `huginn_muninn_run` projections; figures
(`Figures`) and the checklist with the light (`Checks`); the nightly run
(`NightlyWorker`); the figures, light and checks routes under
`/v1/residents/:id`; the `root_mismatched_at` column on the resident row
(agathos-daimon #20).

## #2 Standing decisions

Carried from spec §6.13; the reason for each is there.

- **#3 Audits read the reference graph, the audit log and the modification logs, never transcript text; results are private to the dyad; never a leaderboard.**
- **#4 Counters are steward-defined keys incremented by events with their actor; the light's findings are the failing results of the audits that count.**
- **#5 The coherence work ships as a runnable checklist first; citation drift and the journal delta are the first two built-in audits.**
- **#8 Figures generalise counters (spec §6.13, F57).** One row kind for a counter, the fold of its increment events, and a countdown derived from a date; both citeable, taggable and rendered fresh in the index, and both what the number rule of spec §6.4 resolves against.

Decided in the build:

- **#9 A counter is a key the steward names and a value nobody writes.** `define_counter/4` and `retire_counter/3` are the steward's; `increment/5` is either party's, by a non-zero integer (negative corrects) with a note, and the event carries the actor, so a concession counted by the resident's tool and one counted by the steward are told apart on the row (the concession-count pattern). The projection folds the value; the aggregate folds it too, for its own rules; neither is ever set.
- **#10 A countdown is a figure read from the schedule, never a row here.** `figures/1` lists the counters and then every date's countdown as `date/<number>` with its days-to derived now (sunna #15); `figure/2` finds either by key, so `<slug>:figure/date/3` resolves like `<slug>:figure/tea`. The brain's `figures` section carries the counters alone, because the dates section already carries the countdowns and one place is the rule.
- **#11 A steward's audit is a rule over a figure, and the built-in checklist reads rows.** `define_audit/3` names a figure, a comparison (`>=`, `<=`, `==`, `>`, `<`), an integer, a tone when it fails (`warn` or `fail`) and whether it counts toward the light. The built-in audits, with whether each counts: the last backup's root matched (`attestation`, counts), no capture failure is open (`capture_failures`, counts), the last twenty turns reached Honcho (`sync_failures`, counts), fewer than `HUGINN_MUNINN_MISSED_CHECKINS_WARN` check-ins missed this week (`missed_checkins`, warns, does not count), no prediction past due unresolved (`overdue_predictions`, warns, does not count). Citation drift and the journal's delta join when the library and the journal do (#5).
- **#12 Every run is an event with a tone, and the light is read from the latest.** `run_audits/2` records `AuditRun{key, builtin, tone, value, finding}` for every audit, built-in and the steward's, nightly at 05:00 UTC after the judgement pass for every active resident (a cross-tenant job under the platform scope, named here) and by hand from the client. `light/1` takes each audit's latest run; the findings are those of the audits that count whose tone is not ok, and the state is fail if any of them fails, warn if any warns, else ok. A result is never a leaderboard: nothing here compares residents.
- **#13 The brain reads and increments, never defines.** `figure_list` and `figure_increment` are the resident's tools (brain #20); the `figures` section is a recorded injection on every turn with counters, derived on that read.

## #6 Initial vs target

Initial (P2, slice 4): #9 to #13. Target: citation drift and the
journal's plan-vs-actuals delta as built-in audits with the library and
the journal (P3), the composite coherence score once there is a decision
for it to feed (spec §6.13), the Audits screen and the light in Chat's
top bar.

## #7 Depends on

The resident system for the row and the roster; the schedule for the
dates and the firings; memory for the open capture failures; the bridge
for the syncs; judgement for the open predictions. The brain depends on
this system for the figures and the tools, and this system never
reaches the brain.
