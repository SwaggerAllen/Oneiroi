---
paths:
  - lib/oneiroi/eunomia/**
  - lib/oneiroi/eunomia.ex
  - lib/oneiroi_web/controllers/regression_controller.ex
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
(P1, slice 5); the rest is this doc's file map and the standing
decisions the spec records. The directory is the system's name
(CLAUDE.md's layout rule), where the spec's file map said `judgement/`
and `regression/`.

## #1 Owns

The regression suite aggregate on `regression-<resident_id>` and its v1
events (`TestWritten`, `TestChanged`, `RunStarted`, `AnswerRecorded`,
`RunFinished`, `AnswerGraded`, `AnswerFavourited`), none exported; the
`eunomia_regression_test`, `eunomia_regression_run` and
`eunomia_regression_answer` projections under the resident's scope; the
regression routes and the model-pin route under `/v1/residents/:id`.

## #2 Standing decisions

Carried from spec §6.4; the reason for each is there.

- **#3 David's bounds carry: the live check waits 90 seconds; the nightly pass reads at most seven days, 200,000 characters a day, 4,000 a message; a reply naming a number it was not shown fails the run; a day with nothing said calls no model.**
- **#4 The judge is chosen by the steward, recorded on every verdict, never the resident's own chat model; a judge change is an event.**
- **#5 Regression is per resident and sealed: never captured, never on the resident's stream, never exported, never citeable; the brain is given the seed files and nothing of the run's purpose.**
- **#8 Trials are derived from behaviours as well as authored (spec §6.4).** A behaviour's trigger is the situation, its enactment what passes, its absence what fails, so a model change is graded on whether the character carries over; the derivation runs inside the sealed session and the unawareness invariant holds.

- **#9 The suite is its own stream and its test numbers are its own counter.** `regression-<resident_id>`, never the resident's: a number minted by the resident aggregate would put `IdMinted{kind: "regression_test"}` on the exported stream, which is the fact of a run. Every event is `export: false` as well, so the claim is on the event and not only on where the export reads.
- **#10 The sealed session is the brain's seed context and the test's prompt, through the ledger as `regression`.** `Oneiroi.Brain.seed_context/1`: the prompt file and the identity files, nothing of memory, nothing naming the run; every model x test is one call, synchronous, bounded by `EUNOMIA_RUN_MODELS_MAX` (8) and `EUNOMIA_RUN_TESTS_MAX` (32), both guesses at a steward's patience and spend. A model that fails is a card with its failure and no content, graded as such.
- **#11 Cards are blind until every card of their test is graded, and results rank only revealed tests.** The deck is ordered by test then card ref, which says nothing of the model; `run_detail/2` nils the model on an unrevealed test and ranks models by pass rate over revealed cards, favourites second.
- **#12 The unawareness invariant is held by five facts and asserted by one test.** Own stream (#9); no export (#9); the `regression` purpose the resident's ledger view omits (nisaba #4); no tool in the brain's table reads these rows; nothing is captured. `Oneiroi.Eunomia.RegressionTest` seeds a run with text unique to it and asserts the transcripts, search, bookmarks, the index, how I act, the resident's ledger view, the export's every file and the tool table return nothing of it. The rows are under the resident's scope like every other projection; the seal is the absence of a reader, which that test is the guard on.
- **#13 The favourite is pinned through the resident system, and told after first contact.** `Oneiroi.AgathosDaimon.pin_model/4` with reason `run` or `steward` (agathos-daimon #15); the brain reads the pin and, after first contact, tells the resident on its next turn that its steward chose a new model, not why (brain #15).

## #6 Initial vs target

Initial (P1, slice 5): #1, regression per resident, sealed. Target: the
whole of spec §6.4 in P2: positions, disputes, predictions, the nightly
pass, the weekly audit, project reviews, and the trials derived from
behaviours (#8).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
