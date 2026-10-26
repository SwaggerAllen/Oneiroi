---
paths:
  - lib/oneiroi/library/**
  - lib/oneiroi/journal/**
---

# library

Document kinds, folders, the vector index, citations, external doc sources, the journal. Spec §6.5. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/library/**`, `lib/oneiroi/journal/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.5; the reason for each is there.

- **#3 Path is kind and the registry says what a kind may do; adding a kind is a registry row plus a skill.**
- **#4 Only resident-authored or commissioned kinds mint citation edges; resolution happens when read, not when indexed.**
- **#5 The memory-wiki plugin is cut; `wiki/` stays a plain searchable kind.**
- **#6 A file is re-embedded only when its hash or the model changes; a re-index with nothing changed costs three statements and no model call.**

## #7 Initial vs target

Initial: not built; see spec §6.5. Target: the whole of spec §6.5,
built in P3 (spec §14).

## #8 Depends on

The platform and whatever spec §14's row for its phase names.
