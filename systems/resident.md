---
paths:
  - lib/oneiroi/resident/**
  - lib/oneiroi/resident.ex
  - lib/oneiroi_web/controllers/resident_controller.ex
  - priv/repo/migrations/*_resident.exs
  - test/oneiroi/resident/**
---

# resident

The resident aggregate: creation, lifecycle, custody, the per-resident id
sequences, and the records bookkeeping on its stream (spec §6.2). Built
attended in the same pass as the spine (plan P0.6, decisions log round
9), so the first export had a stream to read.

## #1 Owns

The Resident aggregate on `resident-<id>` and its v1 events
(`ResidentCreated`, `IdMinted`, `ResidentPaused`, `ResidentWoken`,
`CustodyTransferred`, `ExportWallSet`, `Imported`, `ExportWritten`,
`BackupCommitted`, `RootMismatchDetected`, `RecordsRemoteSet`); the
`resident_resident` projection, scoped by both the resident and its
steward's account; the custody wire form (`account:<id>`, `community`);
the `/v1/residents` routes.

## #2 Standing decisions

- **#3 Creation is a name and a slug.** The creation flow with its
  threshold and gifts is P1 (spec §6.2): the threshold collects a key the
  ledger does not yet exist to hold. The slug is platform-wide and
  checked under the platform scope before dispatch.
- **#4 Per-resident id sequences are aggregate state.** A counter per
  kind, held in the aggregate and advanced by `IdMinted{kind, number}`,
  so an event that mints a citeable id carries it without a second
  event and replay reproduces it exactly; the property tests assert both
  that and that two residents never interleave.
- **#5 The projection is scoped both ways.** `resident_id` is the row's
  own id and `account_id` its current steward's, so the resident's scope
  and the steward's each see it and nobody else does; a custody move
  rewrites `account_id` in the same fold.
- **#6 The records bookkeeping lives on this stream, and some of it is not
  exported.** `ExportWritten` and `BackupCommitted` are `export: false`:
  facts about the repository, kept for the dashboard and the next run,
  and exporting them meant every nightly backup changed the export it
  had just made. `RecordsRemoteSet` is exported with its token redacted;
  `RootMismatchDetected` and `Imported` are the resident's history and
  are exported.
- **#7 An imported stream is a new resident with a derived slug and no
  remote.** The projector reads `imported` from the replayed events'
  metadata: the slug becomes the source's slug suffixed with the first
  eight hex digits of the new id, because the source may still be in
  this store (spec §6.2: a move cannot be told from a copy), and the
  source's own remote, export and backup marks are history rather than
  the new resident's state, or the nightly job would push a copy to the
  source's repository.

## #8 Initial vs target

Initial (P0): #1 with creation, id minting, custody and the records
events reachable through the API or the records system; pause and wake
have no command edge yet. Target: the four-stage creation flow with the
nine gifts, first contact and proposals, the subscription and its
lifecycle events, succession (spec §6.2).

## #9 Depends on

The platform (the kernel). The identity system reads this stream for
stewardship; the records system writes this stream's bookkeeping.
