---
paths:
  - lib/oneiroi/schedule/**
---

# schedule

Check-ins, the digest's time, free time, nightly and weekly jobs. Spec §6.7. Not built; this doc is its file map, the
standing decisions the spec already records, and the phase that builds
it, so a design pass reaching for it finds a record rather than a gap.

## #1 Owns

`lib/oneiroi/schedule/**`, none of it in the tree yet.

## #2 Standing decisions

Carried from spec §6.7; the reason for each is there.

- **#3 Oban-driven, per resident, in the resident's timezone; a check-in fires once a day whatever restarts, late within 15 minutes and otherwise missed.**
- **#4 Quiet hours are the steward's; a wake queued inside them is deferred to their end and the screen says so in words.**
- **#5 Suspended residents schedule nothing; a wake resumes the beat.**

## #6 Initial vs target

Initial: not built; see spec §6.7. Target: the whole of spec §6.7,
built in P2 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
