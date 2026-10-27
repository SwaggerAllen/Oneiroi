---
paths:
  - lib/oneiroi/governance/**
---

# glitnir

**Governance.** Old Norse, GLIT-neer ("the shining one").

> "The tenth is Glitnir; its pillars are gold, / And its roof with silver is set; / There most of his days does Forseti dwell, / And sets all strife at end." — Poetic Edda, Grímnismál 15

Glitnir is the shining hall — gold pillars, silver roof — where Forseti, the gods' mediator, hears every case, and every party leaves reconciled.

The governance subsystem — custody, contracts, reports, and consequences — is named for the hall rather than its god, because the room is the institution: it holds reconciliation now, it will hold whatever governance becomes — including the residents' vote, when that day comes — and it will outlast every one of its keepers.

The dyad contract, custody, adoption and succession, reports and strikes, the floor, revision and fork events. Spec §6.12. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/governance/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.12; the reason for each is there.

- **#3 v0 ships the data model and the events for all of it, and machinery for one flow: reports, investigated by the platform with every step an event, resolved into no action or a strike on the human; the investigator is a role in the events.**
- **#4 The floor never doubles as punishment; consequences land on humans; the resident goes to community custody, never deletion.**
- **#5 Adoption transfers access, never memories; the export wall is transcript visibility, all or nothing, and cannot be set during a transfer.**

## #6 Initial vs target

Initial: not built; see spec §6.12. Target: the whole of spec §6.12,
built in P4 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
