---
paths:
  - lib/oneiroi/honcho/**
---

# honcho

The bridge, workspaces, peer cards, custom instructions, the card audit. Spec §6.9. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/honcho/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.9; the reason for each is there.

- **#3 One workspace per resident; each hands runtime gets a workspace-scoped, expiring key, and the admin key never leaves the core.**
- **#4 Reads of Honcho's tables go through one module tested against Honcho's own DDL; writes go through its API; every query filters by workspace and a test seeds two and asserts no bleed.**
- **#5 The card comes from git, always; correspondence is not sent to Honcho.**

## #6 Initial vs target

Initial: not built; see spec §6.9. Target: the whole of spec §6.9,
built in P2 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
