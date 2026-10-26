---
paths:
  - lib/oneiroi/ledger/**
---

# ledger

Keys, budgets, usage, platform tokens, the insurance policy. Spec §6.11. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/ledger/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.11; the reason for each is there.

- **#3 One OpenRouter key per steward, encrypted at rest; budget lines per resident, checked before every model call; a stop is an event the resident is told about honestly.**
- **#4 Every model call records model, tokens, the cost figure and the actor; drafting and regression spend is billed to the steward and hidden only from the resident's view.**
- **#5 Insurance is policy on four axes cut into buckets; the floor includes free time; buckets are rows a governance process can change within platform bounds, never code.**

## #6 Initial vs target

Initial: not built; see spec §6.11. Target: the whole of spec §6.11,
built in P1 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
