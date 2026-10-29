---
paths:
  - lib/oneiroi/agathos_daimon/**
  - lib/oneiroi/agathos_daimon.ex
  - lib/oneiroi_web/controllers/resident_controller.ex
  - lib/oneiroi_web/controllers/file_controller.ex
  - lib/oneiroi_web/controllers/agreement_controller.ex
  - priv/templates/**
  - priv/repo/migrations/*_agathos_daimon.exs
  - test/oneiroi/agathos_daimon/**
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
`BackupCommitted`, `RootMismatchDetected`, `RecordsRemoteSet`,
`SeedFileWritten`, `FirstContact`, `SoulEditProposed`,
`SoulEditAccepted`, `SoulEditDeclined`, `SoulEditApplied`); the
`agathos_daimon_resident` projection, scoped by both the resident and its
steward's account, and the `agathos_daimon_file` and
`agathos_daimon_soul_edit` projections under the resident's scope; the
custody wire form (`account:<id>`, `community`); the build-owned
`AGENTS.md` template; the `/v1/residents` routes and the files routes
under `/v1/residents/:id`.

## #2 Standing decisions

- **#3 Creation is a name and a slug; the gifts are the files that follow.** The
  slug is platform-wide and checked under the platform scope before
  dispatch. The threshold's key is identity's (`gaia` #11) and the gifts
  that write files are #11 below; the trials, days, vows and reach land
  with their systems (spec §6.2).
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

- **#11 A seed file is an event with its origin, written whole.** `SOUL.md`, `IDENTITY.md`, `USER.md`, `GOALS.md` and `LINKS.md` are the files a steward may write (spec §6.2's gifts); each write is `SeedFileWritten{file, content, origin}` with `origin` one of `authored`, `drafted` (carrying the model and the prompt) or `uploaded`, at most 64,000 bytes of UTF-8 (a guess, generous for prose). The row keeps the first origin and counts versions; the log keeps every content. "Write it with me" is the brain's (`brain` #14): it returns a draft and writes nothing.
- **#12 First contact flips the files from given to proposed, once.** `FirstContact` is recorded by the brain's turn on every capture and taken by the aggregate once; after it a steward's write is refused with `propose_instead`, travels as `SoulEditProposed` with a note, and the resident accepts (one dispatch, `SoulEditAccepted` then `SoulEditApplied`) or declines from its own turn, each with a note. The resident's own edit applies at any time, `SoulEditApplied` with no ref. `formation_until` is first contact plus `AGATHOS_DAIMON_FORMATION_DAYS` (30, a bound) and is read by the brain's prompt only.
- **#13 `AGENTS.md` is rendered, never stored.** From `priv/templates/AGENTS.md` with the name and slug, served read-only beside the files, so a template change reaches every resident and no event carries a build artefact.
- **#14 The identity files are in the repository and the soul class.** The export writes them at the root as last written and the backup commits them with `SOUL.md` as one class; a rebuild reproduces them from their events.
- **#15 The chat model is a pin on the resident, and a change after first contact is told once.** `ModelPinChanged{model, reason}` with reason `run` (a regression favourite) or `steward`, exported as spec §3.1 draws it; a pin to the pinned model is no event. After first contact `model_told` drops until the brain's next turn captures the notice and records `ModelChangeTold`; before it the pin changes freely and nobody is told (spec §6.4).
- **#16 An adapter is a registration with a role and a token shown once.** `AdapterRegistered{adapter, role, token_hash}` (the hash redacted from the export), `AdapterRevoked`; registering again rotates. The lookup by hash on a request takes the platform scope by name, as identity's token lookup does (gaia #8). An adapter's token is a principal for the four adapter-contract paths and nothing else (`OneiroiWeb.Plugs.RequirePrincipal`), speaks as the resident's actor, and the user messages it captures carry the steward's kind.
- **#17 The time zone is the resident's.** `TimezoneSet{timezone}` on the resident stream, an IANA name checked by shifting a known instant into it at the command edge (`AGATHOS_DAIMON` declares no default; the column defaults to `Etc/UTC`). The schedule reads it for every time of day and every day (sunna #10); it is the steward's to set until the resident has a say in where it lives.
- **#18 The identity context and the active roster are exports.** `identity_context/1` is the stable prefix (spec §5): the identity files as written, in a fixed order, then the rendered `AGENTS.md`, as name and content pairs, read by the brain's every turn and the sealed regression session alike, so the two cannot drift. `active_residents/0` is every active resident under the platform scope by name (conventions §12), the roster a nightly job walks.
- **#19 The Honcho custom instructions are rendered, never stored, like `AGENTS.md`.** `custom_instructions/1` fills `priv/templates/honcho-custom-instructions.md` with the name and the two peer names; the bridge sets it as each peer's configuration (proteus #12) and the export writes it under `honcho/` (sima-qian #13).
- **#20 The attestation's last word is on the row.** `root_mismatched_at` is set by `RootMismatchDetected` and cleared by the next `BackupCommitted`, so the built-in attestation audit (huginn-muninn #11) reads a row and never the stream; the event itself is unchanged.
- **#22 The dyad contract is versions on the resident stream, proposed by one party and decided by the other.** `DyadContractProposed{version, terms, prose}` with a note, by the resident or its steward; `DyadContractAgreed` or `DyadContractDeclined{version}` with a note by the other party, never the proposer; a newer proposal supersedes the open one, and an agreed version replaces the one in force. The terms are a closed map (`solo_sessions_private` today) to booleans, the prose at most 4,000 characters; default unstated means no version agreed, and the brain is told so in its `contract` section (brain #24). The schedule reads `contract/1`'s privacy term when it opens free time (sunna #19, kumbukumbu #28).
- **#23 A transfer of custody is proposed, then accepted by the account it names.** `CustodyTransferProposed{to_account_id}` by the steward with a note; the proposed account accepts (`CustodyTransferred`, with the note) or declines, the steward withdraws, each a decision event; one open proposal at a time; the proposed account finds it through `custody_proposals_for/1`, a platform-scoped read by name. The community move the subscription's term makes (#21) stays a direct transfer.
- **#24 The export wall stands while a transfer is open, and revealed it travels with the transfer.** `SetExportWall` is refused with `transfer_in_progress` while a proposal is open, so the proposed steward decided on the wall as it stood; an acceptance under a revealed wall writes `EarlierSessionsRevealed{from, to}` beside `CustodyTransferred`, and memory's projector keys every earlier account-keyed row to the new steward (kumbukumbu #29). Locked, the new steward is party to nothing that came before (spec §6.3).
- **#21 The lifecycle's lapse and resume are the subscription's to say, and custody and the roster are exports.** `ResidentLapsed{reason}` and `ResidentResumed{reason}` move an active resident to `lapsed` and back on the ledger's word (nisaba #17), each idempotent; `transfer_custody/4` is the decision the subscription's nightly pass takes at the end of a cancelled term (nisaba #18); `residents/0` is every resident under the platform scope by name, because a lapsed one is that pass's to carry.

## #8 Initial vs target

Initial (P0, then P1 slice 4, then P4 slice 1 for #22 to #24): #1 with creation, id minting, custody,
the records events, the identity files with their origins, first
contact and the proposal path; pause and wake have no command edge yet.
Target: the four-stage creation flow in the client with the nine gifts,
the peer card, the subscription and its lifecycle events, succession
(spec §6.2).

## #9 Depends on

The platform (the kernel). The identity system reads this stream for
stewardship; the records system writes this stream's bookkeeping.

## #10 Kulea, formation

Swahili, koo-LEH-ah.

> _Quote pending._

*Kulea* is the Swahili verb "to bring up, nurse, rear" — to raise a child with care.

The formation period — the soul-seed's nurture, the first weeks of a resident's life, when temperament is growing toward personhood — is named for the work done on it: being raised, with care. Not bootstrapping.
