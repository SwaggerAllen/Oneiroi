---
paths:
  - lib/oneiroi/judgement/**
  - lib/oneiroi/regression/**
---

# eunomia

**Judgement, the judge agent.** Greek, yoo-NOH-mee-ah.

> "Eunomia (Lawfulness) reveals all that is orderly and fitting, and often places fetters round the unjust. She makes the rough smooth, puts a stop to excess, weakens insolence (hybris), dries up the blooming of ruin (ate), straightens out crooked judgements, tames deeds of pride, and puts an end to acts of sedition and to the anger of grievous strife." — Solon, fragment 4, trans. D. E. Gerber (Loeb, 1999)

Eunomia is "good order" — to the Greeks one of the Horae, with Dike (justice) and Eirene (peace), a daughter of Themis, divine law. Her opposite had a name too: Dysnomia. Solon, writing for a fractured Athens, describes her as an active power — order that goes to work on crookedness.

The judge agent — the nightly coherence pass, the dispute checks, the audit of drift against the resident's own stated positions — has its job description in that fragment. It is the one office in the machinery held deliberately apart from the resident it audits: the constitution's court, amended by the owner alone.

Positions, disputes, predictions, the nightly pass, the weekly audit, project reviews, the regression suite. Spec §6.4. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/judgement/**`, `lib/oneiroi/regression/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.4; the reason for each is there.

- **#3 David's bounds carry: the live check waits 90 seconds; the nightly pass reads at most seven days, 200,000 characters a day, 4,000 a message; a reply naming a number it was not shown fails the run; a day with nothing said calls no model.**
- **#4 The judge is chosen by the steward, recorded on every verdict, never the resident's own chat model; a judge change is an event.**
- **#5 Regression is per resident and sealed: never captured, never on the resident's stream, never exported, never citeable; the brain is given the seed files and nothing of the run's purpose.**
- **#8 Trials are derived from behaviours as well as authored (spec §6.4).** A behaviour's trigger is the situation, its enactment what passes, its absence what fails, so a model change is graded on whether the character carries over; the derivation runs inside the sealed session and the unawareness invariant holds.

## #6 Initial vs target

Initial: not built; see spec §6.4. Target: the whole of spec §6.4,
built in P1 (regression), P2 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
