---
paths:
  - lib/oneiroi/audits/**
---

# audits

User-authored audits, counters, the coherence checklist, the check-engine light. Spec §6.13. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/audits/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.13; the reason for each is there.

- **#3 Audits read the reference graph, the audit log and the modification logs, never transcript text; results are private to the dyad; never a leaderboard.**
- **#4 Counters are steward-defined keys incremented by events with their actor; the light's findings are the failing results of the audits that count.**
- **#5 The coherence work ships as a runnable checklist first; citation drift and the journal delta are the first two built-in audits.**

## #6 Initial vs target

Initial: not built; see spec §6.13. Target: the whole of spec §6.13,
built in P2 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
