---
paths:
  - lib/oneiroi/hands/**
  - lib/oneiroi/adapters/**
  - runtime/openclaw/**
  - runtime/claude-code/**
---

# dioscuri

**Hands, runtimes.** Greek, dee-OSS-koo-ree.

> "Castor the tamer of horses, and the boxer Polydeuces. These two the earth, the giver of life, covers, albeit alive, and even in the world below they have honor from Zeus. One day they live in turn, and one day they are dead; and they have won honor like unto that of the gods." — Homer, Odyssey 11.298–304, trans. A. T. Murray (Loeb, 1919)

Castor and Polydeuces — the Dioscuri, the heavenly twins — are brothers with different fathers: one mortal, one a son of Zeus. When the mortal twin died, the immortal refused heaven without him, and Zeus let them share it: alive and dead on alternating days. They are the protectors of sailors; the light on the masthead was theirs.

The hands — the runtimes, the worker agents that act for the resident in the world — are named for the pair. One builds, one ranges and reads; they are the resident's legs and eyes out in the weather, not only makers. And the myth's core is the worker design itself: loyalty — neither one without the other's turn.

Agent runtimes and the three-interface contract; the worker and reader queues; wake fan-out. Spec §6.8. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/hands/**`, `lib/oneiroi/adapters/**`, `runtime/openclaw/**`, `runtime/claude-code/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.8; the reason for each is there.

- **#3 One OpenClaw gateway per tenant, pinned by digest, hosting a reader and a worker with per-agent tool profiles; the reader never carries the worker's push token.**
- **#4 The platform never holds a witness's Claude subscription token; Claude Code is a brain adapter where the token stays theirs.**
- **#5 One running step per tenant's hands; the resident is told by wake and never given results in the wake text.**
- **#6 Wake fan-out is keyed and coalesced; a refused session key falls back to main and is counted, never quiet.**

## #7 Initial vs target

Initial: not built; see spec §6.8. Target: the whole of spec §6.8,
built in P1 (the Claude Code adapter), P5 (spec §14).

## #8 Depends on

The platform and whatever spec §14's row for its phase names.

## #9 Gjallarhorn, the wake fan-out

Old Norse, GYAH-lar-horn.

> "He has a trumpet called the Gjallarhorn, and when he blows it it can be heard in all the worlds." — Snorri Sturluson, Prose Edda, Gylfaginning 27, trans. R. B. Anderson (1901)

The Gjallarhorn is the horn of Heimdall, the gods' watchman: a blast that carries through every world at once — and at the end of the world, its sounding is how everyone everywhere knows.

The wake fan-out — the notice that a task has finished, routed to whoever asked for it — is named for the instrument. A blast that could be missed would not be a blast. The name takes the horn, not the watchman.
