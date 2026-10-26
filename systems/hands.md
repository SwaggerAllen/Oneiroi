---
paths:
  - lib/oneiroi/hands/**
  - lib/oneiroi/adapters/**
  - runtime/openclaw/**
  - runtime/claude-code/**
---

# hands

Agent runtimes and the three-interface contract; the worker and reader queues; wake fan-out. Spec §6.8. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/hands/**`, `lib/oneiroi/adapters/**`, `runtime/openclaw/**`, `runtime/claude-code/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.8; the reason for each is there.

- **#3 One OpenClaw gateway per tenant, pinned by digest, hosting a reader and a worker with per-agent tool profiles; the reader never carries the worker's push token.**
- **#4 The platform never holds a steward's Claude subscription token; Claude Code is a brain adapter where the token stays theirs.**
- **#5 One running step per tenant's hands; the resident is told by wake and never given results in the wake text.**
- **#6 Wake fan-out is keyed and coalesced; a refused session key falls back to main and is counted, never quiet.**

## #7 Initial vs target

Initial: not built; see spec §6.8. Target: the whole of spec §6.8,
built in P1 (the Claude Code adapter), P5 (spec §14).

## #8 Depends on

The platform and whatever spec §14's row for its phase names.
