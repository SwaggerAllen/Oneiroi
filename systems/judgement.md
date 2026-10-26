---
paths:
  - lib/oneiroi/judgement/**
  - lib/oneiroi/regression/**
---

# judgement

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

## #6 Initial vs target

Initial: not built; see spec §6.4. Target: the whole of spec §6.4,
built in P1 (regression), P2 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
