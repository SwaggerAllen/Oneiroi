---
paths:
  - lib/oneiroi/audits/**
---

# huginn-muninn

**Audits.** Old Norse, HOO-gin and MOO-nin ("thought and memory").

> "O'er Mithgarth Hugin and Munin both / Each day set forth to fly; / For Hugin I fear lest he come not home, / But for Munin my care is more." — Poetic Edda, Grímnismál 20, trans. H. A. Bellows (1923)

Thought and Memory are the watcher god's two ravens: out at dawn over the whole world, home by dinner, telling him everything they saw. The poem carries its own honest line — the fear of losing Huginn, and of losing memory most of all.

The audits subsystem — the coherence pass that flies out over everything the realm has said and comes home to report — is named for the daily flight. An audit that might not come back is the only kind worth trusting with the truth.

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
- **#8 Figures generalise counters (spec §6.13, F57).** One row kind for a counter, the fold of its increment events, and a countdown derived from a date; both citeable, taggable and rendered fresh in the index, and both what the number rule of spec §6.4 resolves against.

## #6 Initial vs target

Initial: not built; see spec §6.13. Target: the whole of spec §6.13,
built in P2 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
