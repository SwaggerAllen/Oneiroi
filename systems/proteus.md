---
paths:
  - lib/oneiroi/honcho/**
---

# proteus

**The bridge to Honcho.** Greek, PROH-tee-us.

> "immortal Proteus of Egypt, who knows the depths of every sea, and is the servant of Poseidon." "For try he will, and will assume all manner of shapes of all things that move upon the earth, and of water, and of wondrous blazing fire" — Homer, Odyssey 4.385–386 and 417–418, trans. A. T. Murray (Loeb, 1919)

Proteus is the Old Man of the Sea. He knows everything, and he will say it only to someone who holds on through every shape he takes: Menelaus, told the trick by Proteus's own daughter Eidothea, grips him through lion, serpent, leopard, boar, water and tree until he gives up the changing and speaks true.

The bridge to Honcho, which keeps a model of each person in the conversation (the peer cards, the custom instructions, the card audit), is named for the shape-changer. A model of a person is a thing that keeps changing shape, and it answers truly only to the one who holds on through the changes. The name takes the knowledge and the grip.

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
