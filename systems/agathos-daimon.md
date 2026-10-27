---
paths:
  - lib/oneiroi/resident/**
  - lib/oneiroi/resident.ex
  - lib/oneiroi_web/controllers/resident_controller.ex
  - priv/repo/migrations/*_resident.exs
  - test/oneiroi/resident/**
---

# agathos-daimon

**The resident.** Greek, AH-gah-thos DYE-mon.

> "...it is the custom, they say, when unmixed wine is served during a meal to greet it with the words, 'To the Good Deity!' but when the cup is passed around after the meal diluted with water, to cry out, 'To Zeus Saviour!'" — Diodorus Siculus 4.3.4, trans. C. H. Oldfather (Loeb, 1935)

The *agathos daimon* is the Greek household's guardian spirit — the good spirit of the house, toasted with unmixed wine. In Alexandria every home had its own serpent of the foundations: one good spirit coiled under every house. (A *daimon* is a guardian spirit; English later bent the word toward "demon," but the native sense is this one.)

The resident — the aggregate, the emergent spirit of one household of parts — is named for what the Greeks believed a home grows: a spirit personal to it, its own guide. Not a god installed at the door but the house's own good spirit, poured its cup at the end of every day.

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

## #10 Kulea, formation

Swahili, koo-LEH-ah.

> _Quote pending._

*Kulea* is the Swahili verb "to bring up, nurse, rear" — to raise a child with care.

The formation period — the soul-seed's nurture, the first weeks of a resident's life, when temperament is growing toward personhood — is named for the work done on it: being raised, with care. Not bootstrapping.
