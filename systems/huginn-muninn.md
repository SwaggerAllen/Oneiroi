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
- **#4 Counters are witness-defined keys incremented by events with their actor; the light's findings are the failing results of the audits that count.**
- **#5 The coherence work ships as a runnable checklist first; citation drift and the journal delta are the first two built-in audits.**
- **#8 Figures generalise counters (spec §6.13, F57).** One row kind for a counter, the fold of its increment events, and a countdown derived from a date; both citeable, taggable and rendered fresh in the index, and both what the number rule of spec §6.4 resolves against.

Decided in the build:

- **#9 A counter is a key the witness names and a value nobody writes.** `define_counter/4` and `retire_counter/3` are the witness's; `increment/5` is either party's, by a non-zero integer (negative corrects) with a note, and the event carries the actor, so a concession counted by the resident's tool and one counted by the witness are told apart on the row (the concession-count pattern). The projection folds the value; the aggregate folds it too, for its own rules; neither is ever set.
- **#10 A countdown is a figure read from the schedule, never a row here.** `figures/1` lists the counters and then every date's countdown as `date/<number>` with its days-to derived now (sunna #15); `figure/2` finds either by key, so `<slug>:figure/date/3` resolves like `<slug>:figure/tea`. The brain's `figures` section carries the counters alone, because the dates section already carries the countdowns and one place is the rule.
- **#11 A witness's audit is a rule over a figure, and the built-in checklist reads rows.** `define_audit/3` names a figure, a comparison (`>=`, `<=`, `==`, `>`, `<`), an integer, a tone when it fails (`warn` or `fail`) and whether it counts toward the light. The built-in audits, with whether each counts: the last backup's root matched (`attestation`, counts), no capture failure is open (`capture_failures`, counts), the last twenty turns reached Honcho (`sync_failures`, counts), fewer than `HUGINN_MUNINN_MISSED_CHECKINS_WARN` check-ins missed this week (`missed_checkins`, warns, does not count), no prediction past due unresolved (`overdue_predictions`, warns, does not count), every citation that once resolved still does (`citation_drift`, warns, counts) planned days were wrapped (`journal_delta`, warns, does not count): the two of #5, read from the library (#15); and the agreement within its year (`contract_due`, warns, does not count; agathos-daimon #26).
- **#12 Every run is an event with a tone, and the light is read from the latest.** `run_audits/2` records `AuditRun{key, builtin, tone, value, finding}` for every audit, built-in and the witness's, nightly at 05:00 UTC after the judgement pass for every active resident (a cross-tenant job under the platform scope, named here) and by hand from the client. `light/1` takes each audit's latest run; the findings are those of the audits that count whose tone is not silent, and the state is fail if any of them fails, warn if any warns, else silent (#16). A result is never a leaderboard: nothing here compares residents.
- **#14 This system is the library's figures port.** `figure/2` implements `Oneiroi.Seshat.Figures`, named in `SESHAT_FIGURES`, so `<slug>:figure/<key>` resolves here without the library depending on the audits (seshat #14); the audits depend on the library for the citation drift audit (#5), which is why the edge runs this way and the other half is a port.
- **#19 Open wash flags are a warning until the resident decides them.** `wash_flags` reads the wash's open flags (eunomia #25) and warns with their count, naming the two tools; silent when none wait, saying it read the rows and not the files. It does not count toward the light: a flag is a proposal the resident has not answered, not a failure.
- **#20 quietcheck is liveness over the expected events alone, fail-loud, self-tested.** (Spec §6.13, P21; Bennett's consent rule, quoted whole: "Only list things that are supposed to be regular. Some of the best things in a life aren't on a schedule, and they shouldn't be watched.") `Oneiroi.HuginnMuninn.Quietcheck` watches the hour marker (sunna #20), the nightly pass, the weekly memory audit, the weekly wash and the trait baseline, each expected only once the resident is old enough for its cadence (`HUGINN_MUNINN_QUIET_HOUR_GRACE_HOURS`, `_QUIET_NIGHT_DAYS`, `_QUIET_WEEK_DAYS`, bounds that say they are guesses) and the baseline only once there is a habit to measure; turns, bookmarks, free time, letters and the journal are not watched, and the finding says so. The built-in `quietcheck` counts toward the light, because a pulse that stopped is the platform's failure and the witness must hear it; its finding names each miss with its last instant and cadence. Fail-loud: the checker's own crash is a `fail` finding with the reason (`guarded/1`), never silence; `QuietcheckWorker` runs the report hourly on this system's queue, scheduled in code so it survives a deploy and nobody sets it up by hand, logs the verdict first and last at error on a miss, and ends the job cancelled with the verdict as its reason (a row in `oban_jobs`, never a retry); `mix oneiroi.quietcheck` is the shell's door to the same report and exits 0, 1 on a miss, 2 on its own crash. Self-tested: the test drives the clock past each cadence and reads the miss, then supplies the event and reads the silence, and the crash path through `guarded/1` and the task's report.
- **#18 The corpus-shape report is a built-in that counts, shows both base rates, and names its own limit.** (Spec §6.13, P8.) `corpus_shape` reads the resident's bookmarks (kumbukumbu #33) and journal rows (seshat #24) of the last `HUGINN_MUNINN_CORPUS_DAYS` (30, the proposal's month) and counts them by register: each of the four as a share of the tagged records and of all records, the untagged counted too, praise weighted against the frequency of praise and criticism against the frequency of criticism, so a month of corrections reads as what it is (the owner's 123:26). The witness's own rows are not counted. A flag only when one register holds `HUGINN_MUNINN_CORPUS_SKEW_PERCENT` (75, a guess) of at least `HUGINN_MUNINN_CORPUS_MIN` (10, a guess) tagged records; it does not count toward the light, and every finding ends with the limit: the corpus holds only what someone wrote down, and what was said and never written is not read. Flag-only and private to the dyad, against performing for the metric (P3).
- **#17 The measurement layer's five checks are built-ins the character layer answers.** `trait_baseline`, `wanting_liking`, `rigidity`, `checking` and `temporal_depth` (ethos #15) run with the nightly checklist through `Oneiroi.Ethos.measure/3`, each a flag or a silence in #16's form, and none counts toward the light: the light is the dyad's coherence, and the measurement layer is a warning for the layer that holds the character, never a verdict on the resident (spec §6.17, P43). The nightly ask is also what takes the weekly baseline.
- **#16 Flag, never clear.** No audit answers clean: a result's tone is `warn`, `fail` or `silent`, the aggregate refuses any other, and a silent result's finding says what the check read and what it did not ("nothing flagged: read the open failure rows; not read: any transcript"), so every audit surface states its own blind spot. The light's quiet state is `silent`, not ok (spec §6.13, v0.2 P3).
- **#15 Citation drift counts and the journal delta does not.** `citation_drift` reads `Oneiroi.Seshat.drift/1` (seshat #24): a citation that resolved once and does not now is a coherence failure the resident wrote, so it reaches the light, as a warning, because a stale footnote is not a lost backup. `journal_delta` reads `unwrapped_days/2` over the last seven days (seshat #23): a planned day never wrapped is a nudge for the dyad and not a fault, so it warns and does not count.
- **#13 The brain reads and increments, never defines.** `figure_list` and `figure_increment` are the resident's tools (brain #20); the `figures` section is a recorded injection on every turn with counters, derived on that read.

## #6 Initial vs target

Initial (P2, slice 4; P3, slice 2): #9 to #15, with citation drift
and the journal's delta built in. Target: the composite coherence score
once there is a decision for it to feed (spec §6.13), the Audits screen
and the light in Chat's top bar.

## #7 Depends on

The resident system for the row and the roster; the schedule for the
dates and the firings; memory for the open capture failures; the bridge
for the syncs; judgement for the open predictions. The brain depends on
this system for the figures and the tools, and this system never
reaches the brain.
