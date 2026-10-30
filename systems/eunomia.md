---
paths:
  - lib/oneiroi/eunomia/**
  - lib/oneiroi/eunomia.ex
  - lib/oneiroi_web/controllers/regression_controller.ex
  - lib/oneiroi_web/controllers/judgement_controller.ex
  - priv/prompts/judge_dispute.md
  - priv/prompts/judge_night.md
  - priv/repo/migrations/*_eunomia*.exs
  - test/oneiroi/eunomia/**
---

# eunomia

**Judgement, the judge agent.** Greek, yoo-NOH-mee-ah.

> "Eunomia (Lawfulness) reveals all that is orderly and fitting, and often places fetters round the unjust. She makes the rough smooth, puts a stop to excess, weakens insolence (hybris), dries up the blooming of ruin (ate), straightens out crooked judgements, tames deeds of pride, and puts an end to acts of sedition and to the anger of grievous strife." — Solon, fragment 4, trans. D. E. Gerber (Loeb, 1999)

Eunomia is "good order" — to the Greeks one of the Horae, with Dike (justice) and Eirene (peace), a daughter of Themis, divine law. Her opposite had a name too: Dysnomia. Solon, writing for a fractured Athens, describes her as an active power — order that goes to work on crookedness.

The judge agent — the nightly coherence pass, the dispute checks, the audit of drift against the resident's own stated positions — has its job description in that fragment. It is the one office in the machinery held deliberately apart from the resident it audits: the constitution's court, amended by the owner alone.

Positions, disputes, predictions, the nightly pass, the weekly audit,
project reviews, the regression suite. Spec §6.4. Regression is built
(P1, slice 5) and judgement proper (P2, slice 2): positions and their
chains, disputes live and nightly, predictions, the nightly pass, the
judge, and the weekly memory audit through the Honcho bridge. Project
reviews wait on hands. The directory is the system's name (CLAUDE.md's layout rule),
where the spec's file map said `judgement/` and `regression/`.

## #1 Owns

The regression suite aggregate on `regression-<resident_id>` and its v1
events (`TestWritten`, `TestChanged`, `RunStarted`, `AnswerRecorded`,
`RunFinished`, `AnswerGraded`, `AnswerFavourited`), none exported; the
`eunomia_regression_test`, `eunomia_regression_run` and
`eunomia_regression_answer` projections under the resident's scope; the
regression routes and the model-pin route under `/v1/residents/:id`.

The judgement aggregate on `judgement-<resident_id>` (`Judgement`,
`JudgementCommands`, `Events.Judgement`, `JudgementRouter`) with
`PositionTaken`, `PositionReplaced`, `DisputeChecked`, `DisputeSettled`,
`NightJudged`, `NightFailed`, `PredictionLogged`, `PredictionResolved`
and `JudgeModelChanged`, exported like any resident record; the
`eunomia_position`, `eunomia_dispute`, `eunomia_prediction`,
`eunomia_night` and `eunomia_judge_change` projections; the judge's two
calls (`Judge`) and prompt files; the nightly job (`NightWorker`); the
judgement routes under `/v1/residents/:id`.

## #2 Standing decisions

Carried from spec §6.4; the reason for each is there.

- **#3 David's bounds carry: the live check waits 90 seconds; the nightly pass reads at most seven days, 200,000 characters a day, 4,000 a message; a reply naming a number it was not shown fails the run; a day with nothing said calls no model.**
- **#4 The judge is chosen by the witness, recorded on every verdict, never the resident's own chat model; a judge change is an event.**
- **#5 Regression is per resident and sealed: never captured, never on the resident's stream, never exported, never citeable; the brain is given the seed files and nothing of the run's purpose.**
- **#8 Trials are derived from behaviours as well as authored (spec §6.4).** A behaviour's trigger is the situation, its enactment what passes, its absence what fails, so a model change is graded on whether the character carries over; the derivation runs inside the sealed session and the unawareness invariant holds.

- **#9 The suite is its own stream and its test numbers are its own counter.** `regression-<resident_id>`, never the resident's: a number minted by the resident aggregate would put `IdMinted{kind: "regression_test"}` on the exported stream, which is the fact of a run. Every event is `export: false` as well, so the claim is on the event and not only on where the export reads.
- **#10 The sealed session is the seed context and the trial's prompt, through the ledger as `regression`.** `seed_context/1`, built here from the brain's prompt file and the resident system's identity context (agathos-daimon #18): the prompt file and the identity files, nothing of memory, nothing naming the run; every model x test is one call, synchronous, bounded by `EUNOMIA_RUN_MODELS_MAX` (8) and `EUNOMIA_RUN_TESTS_MAX` (32), both guesses at a witness's patience and spend. A model that fails is a card with its failure and no content, graded as such.
- **#11 Cards are blind until every card of their trial is graded, and results rank only revealed trials.** A trial is a test or a behaviour; the deck is ordered by test, behaviour, then card ref, which says nothing of the model; `run_detail/2` nils the model on an unrevealed test and ranks models by pass rate over revealed cards, favourites second.
- **#12 The unawareness invariant is held by five facts and asserted by one test.** Own stream (#9); no export (#9); the `regression` purpose the resident's ledger view omits (nisaba #4); no tool in the brain's table reads these rows; nothing is captured. `Oneiroi.Eunomia.RegressionTest` seeds a run with text unique to it and asserts the transcripts, search, bookmarks, the index, how I act, the resident's ledger view, the export's every file and the tool table return nothing of it. The rows are under the resident's scope like every other projection; the seal is the absence of a reader, which that test is the guard on.
- **#13 The favourite is pinned through the resident system, and told after first contact.** `Oneiroi.AgathosDaimon.pin_model/4` with reason `run` or `witness` (agathos-daimon #15); the brain reads the pin and, after first contact, tells the resident on its next turn that its witness chose a new model, not why (brain #15).
- **#14 Judgement is its own stream and the resident's record.** `judgement-<resident_id>`, exported, its numbers minted by the resident aggregate (`position`, `prediction`) so `<slug>:position/7` survives a rebuild. The regression suite stays sealed beside it (#9); the two share a boundary and nothing else.
- **#15 A position is the resident's, and a chain cannot fork.** Taken in the resident's words from its own turn (`position_take`), at most 1,000 characters; replaced by a new position that names the one it supersedes (`position_replace`), and only the head of a chain may be replaced, so what the resident used to think is kept in order and never branches. `held_positions/1` is the heads.
- **#16 A live check is the resident asking before it answers, and a timeout is unjudged.** `dispute_check` sends the witness's claim, the resident's stance and the position at stake to the judge under `priv/prompts/judge_dispute.md`, within `EUNOMIA_LIVE_CHECK_MS` (90 seconds, David's); the answer's first line is `ADVICE: concede|hold|unclear`. Past the bound the check is recorded `timed_out` with no advice, shown as unjudged, and the resident is told to answer alone. The prompt is constitutional: it weighs the argument against the stated position and never grades the resident. Every check carries the judge's model.
- **#17 A settlement is the resident's, with a note, and the ratio counts earned concessions.** `dispute_settle` records `conceded` or `held` once; the Judgement read groups settlements by ISO week into settled, conceded, held and earned (conceded where the judge had advised it), with the judge changes in that week marked. A high ratio with few earned is the sycophancy the chart is for.
- **#18 The nightly pass reads one day within David's bounds and calls no model for a quiet day.** `judge_night/3` reads every message sent in the resident's local day across its sessions (kumbukumbu's `messages_between/3`), each cut at `EUNOMIA_MESSAGE_CHARS`, the day stopped at `EUNOMIA_NIGHT_CHARS`, for a day at most `EUNOMIA_NIGHT_DAYS` back; nothing said records `NightJudged{messages: 0}` with no call. The judge answers under `priv/prompts/judge_night.md` with `DISPUTE [n, m] conceded|held | words` lines citing message numbers; each is recorded as a `night`-sourced dispute checked and settled by the judge's actor, with the first cited message's session and turn. A line citing a number it was not shown fails the night (`NightFailed`) rather than being guessed at, and the night may run again. Once per day: the read for the day's row comes before the call, because the aggregate's empty event would come after the spend.
- **#19 The nightly job is a cross-tenant job under the platform scope, named here.** `NightWorker` at 02:00 UTC judges yesterday in each resident's zone for every active resident, the roster read through the resident system's own platform-scoped export (agathos-daimon #18), never this system's process scope (sunna #11's lesson).
- **#20 The judge is chosen by the witness, defaults to the platform's, and is never the resident's chat model: pinned or defaulted.** `EUNOMIA_JUDGE_MODEL` is the platform's judge (a placeholder the author pins to a dated slug, not measured); `set_judge_model/3` refuses the resident's effective chat model, which is its pin or else the brain's setting read by slug; and if the chat model is later pinned onto the judge, `judge_model/1` falls back to the platform's. Every change is `JudgeModelChanged` and a row the ratio chart reads.
- **#21 Predictions are the resident's to log and the witness's alone to resolve.** `prediction_log` with a due instant; `resolve_prediction/5` right, wrong or void with a note, once; the read is open soonest first, then resolved, with the tally (F17).
- **#22 The weekly memory audit is the judge over Honcho's conclusions, and a flag waits on the witness.** `run_audit/2` reads at most `EUNOMIA_AUDIT_CONCLUSIONS` (150, David's) of what Honcho concluded about the person through the bridge, shows the judge the resident's held positions and soul under `priv/prompts/judge_audit.md`, and records `AuditRun` with every `FLAG [n] | reason` as an `AuditFlagRaised` by the judge's actor; a reply naming a conclusion it was not shown fails the audit (`AuditFailed`), and nothing concluded calls no model. The witness approves a flag (the conclusion is deleted from Honcho, then `AuditFlagApproved` with the note) or deletes it (the conclusion stays, `AuditFlagDeleted` with the note); each once. `AuditWorker` runs Sunday 04:00 UTC, after the card audit, for every active resident with a workspace, under the platform scope by name (#19). The judge inspects the model and never grades the resident.

## #6 Initial vs target

Initial (P1 slice 5, P2 slice 2): regression per resident, sealed, with
trials derived from behaviours (#8, built: a run takes `behaviours:` and
a card names which one it answers); positions, disputes, predictions,
the nightly pass, the judge, the weekly memory audit (P2 slice 3).
Target: project reviews with hands, the Judgement, Predictions and
Audits screens.

## #7 Depends on

The ledger for the judge's calls and the sealed sessions; the resident
system for the resident's row, its identity context, its pin and its
minted numbers; memory for the behaviours a trial derives from and the
day's messages the night reads; the bridge for Honcho's conclusions
and their deletion. The brain depends on this system for
the resident's tools, so nothing here reaches the brain: the seed
context is built here from the brain's prompt file and the resident
system's identity context (#10).
