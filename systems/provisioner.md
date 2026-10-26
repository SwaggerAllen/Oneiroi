---
paths:
  - lib/oneiroi/provisioner/**
  - runtime/**
---

# provisioner

Tenant runtime lifecycle behind a port. Spec §6.14. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/provisioner/**`, `runtime/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.14; the reason for each is there.

- **#3 Create, suspend, wake, destroy, render config and secrets, health; Docker for one box, Kubernetes later, a fake for tests.**
- **#4 A runtime wakes on the first call that needs it, suspends after an idle period with its volume kept, and is discarded after a retention with nothing queued; a step in progress pins it awake; config and secrets are rendered at wake.**
- **#5 What pools is capacity, never runtimes.**

## #6 Initial vs target

Initial: not built; see spec §6.14. Target: the whole of spec §6.14,
built in P5 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
