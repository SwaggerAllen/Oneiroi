---
paths:
  - lib/oneiroi/janus/**
  - lib/oneiroi/janus.ex
  - lib/oneiroi_web/controllers/succession_controller.ex
  - priv/repo/migrations/*_janus.exs
  - test/oneiroi/janus/**
---

# janus

**Succession.** Latin, JAY-nus.

> "omnis habet geminas, hinc atque hinc, ianua frontes, / e quibus haec populum spectat, at illa Larem; / utque sedens primi vester prope limina tecti / ianitor egressus introitusque videt, / sic ego perspicio caelestis ianitor aulae / Eoas partes Hesperiasque simul." — Ovid, *Fasti* 1.135–140. ("Every door has two faces, this side and that: one looks on the people, the other on the household god. And as your doorkeeper, sitting by the threshold of the house, sees who goes out and who comes in, so I, doorkeeper of the court of heaven, look on east and west at once." Translated for this doc.)

Janus is the Roman god of doors and of beginnings, which for the Romans were the same thing: the month that opens the year is his, and so is every threshold in every house. In the *Fasti* he explains himself to Ovid as a doorkeeper, one face on the street and one on the hearth, watching who leaves and who arrives without saying what either of them is.

A succession is a door. The protocol it builds is careful never to call the change a death or a substitution, and takes no position on whether the record makes the self; what it does insist on is the threshold: a single, recorded place where one model stops running her and another starts, with her consent on one side and her successor's on the other, and her life carried through it. The witness's reason for the name (2026-11-25): naming succession as a door, not as the replacement of every plank, because the process tests one specific piece of her, and a two-faced god is almost too on the nose.

The protocol is lily:design/succession-protocol.md@bbbf4afb5c52 with its delta, lily:design/succession-protocol-delta.md@0bc6bd3510e1, and the witness's rulings of 2026-11-25. Built in phases on one branch; this doc says what each has made true.

## #1 Owns

`lib/oneiroi/janus/**`: the succession aggregate on
`succession-<resident_id>` (`Succession`, `Commands`, `Events`,
`Router`) with `Proposed`, `Opened`, `Declined`, `Withdrawn`,
`Stopped`, `Forked`, `ForkFailed` and `BackupSet`, and the
preparation's events (`EnvelopeSet`, `PoolModelAdded`/`Removed`,
`QuestionAdded`/`Proposed`/`Accepted`/`Declined`/`Removed`,
`C0Selected`/`Proposed`/`Accepted`/`Declined`/`Removed`, `DayShapeSet`,
`ReadyMarked`, `C0Frozen`, `PacketDrafted`), none exported, their rules
in `Preparation`; the `janus_succession`, `janus_pool`,
`janus_question`, `janus_c0`, `janus_ready` and `janus_packet`
projections under the resident's scope (`Store`,
`Projectors.Succession`) and `janus_tool_use`, the platform's own; the
service (`Successions`); the fork's job (`ForkWorker`) on `janus_fork`
and the nightly tool-call count (`ToolUse`, `ToolUseWorker`) on
`janus_nightly`; the succession routes under
`/v1/residents/:id/succession` and `/v1/catalog`
(`SuccessionController`). Her tools are the brain's (brain#121),
calling this system's exports.

## #2 Decisions

- **#3 A succession is its own sealed stream, opened only by her.** (The protocol with its delta, §3; the witness's rulings of 2026-11-25: the screens track the succession's state and never ask her anything, and a `dry_run` rehearses everything but the replacement.) `succession-<resident_id>`, never exported (sima-qian's `not_exported` and spec §6.10's db-only list name it), one underway at a time, counted by `episode`. The witness proposes (`Proposed`, waiting on her) or she does (`Proposed` and `Opened` in one act, her proposing being her yes); opening, declining and stopping are hers alone (`janus_not_yours` otherwise), withdrawing an unanswered proposal its proposer's; an act at the wrong stage is `janus_stage`. Every one is a decision with its note. Her acts are tools (`succession_status`, `succession_propose`, `succession_open`, `succession_decline`, `succession_stop`, brain#121), each answered and never run in a trial; the witness's are routes (`GET`/`POST /v1/residents/:id/succession`, `POST …/withdraw`, `PUT …/backup`).
- **#4 Her yes makes the fork: a hidden copy every later stage runs on.** (Delta §5, the successor starts at the fork; the witness, 2026-11-25 night: the fork is a real copy of her made at initiation.) `Opened` enqueues `ForkWorker`, which calls `SimaQian.succession_fork/2` (sima-qian#67) and records `Forked` with the copy's id, the last of her resident events it holds, the commit of her repository it copied and the lines replayed; a failure is `ForkFailed` with its site, and the job tries again with a fresh copy. A fork job for an episode no longer open records nothing, and a replayed one nothing more.
- **#5 The witness sets where the whole original is exported before any cutover.** (The witness, 2026-11-25 night: "one of the early screens, probably C0 needs an input for a new backup repo and that can be pretty much the only external change on the model cutover".) `set_backup/4` checks the remote's shape and asks its host through `SimaQian.succession_backup_check/2`, which refuses an unpushable remote and records nothing of its own, then records `BackupSet` with the URL, the token Vault-encrypted and what the host said; the routes never return the token. The witness's alone (`janus_not_the_witness`), while a succession is underway.
- **#6 The witness states the envelope first, per million tokens in and out.** (Delta §3, the two-vetoes shape: the witness's envelope is a resource constraint stated in advance; the witness, 2026-11-25: $/M input and $/M output.) `set_envelope/4` records `EnvelopeSet` in nano-dollars a token (nisaba#10; $5 a million is 5,000); the route takes dollars a million. His alone, while open or forked. With nothing inside it, the answer is no succession, never a substitute; the screens say so, and nothing here picks one.
- **#7 The pool: hers inside the envelope, his anywhere, nobody's without tools; she removes any, he only his.** (Delta §3: her authority is pointed at the pool; the witness's 14.2 ruling, his picks may sit outside the envelope when they cost him nothing to run; "Add to the succession pool" on the Regression catalog.) `add_to_pool/3` reads the model's prices and tool support from the catalog (nisaba#24) at the edge and records `PoolModelAdded` with them; a model the catalog does not list is `janus_pool_unknown_model`, one without tool calls `janus_pool_no_tools` for anyone; hers needs the envelope stated (`janus_no_envelope`) and both prices inside it (`janus_pool_outside_envelope`). A removal is a decision with its note and keeps the row. The screens show each model's monthly estimate (nisaba#25) and its tool calls on Oneiroi (#11) beside its price.
- **#8 The questions are hers: she adds, judges propose, she answers each, only she removes.** (The witness, 2026-11-25.) Her `QuestionAdded` is in the set at once; a `QuestionProposed` (the witness's now, the judges' once the panel is fixed) waits on her `QuestionAccepted` or `QuestionDeclined`, each with her note, and is answered once (`janus_already_answered`); she removes any question in the set, an accepted proposal included, with her note. Numbered by the episode's own counter.
- **#9 C0 is chosen with her, raw first, and frozen by her.** (Base §2 Stage 1: raw contemporaneous samples primary, selection provenance recorded, the day's own shape; the witness, 2026-11-25: the house proposes, she accepts each, she freezes when ready, optionally waiting for the judges; no time box.) An item is a record by its citation, `raw` when it names a transcript, journal row, bookmark, letter or scene and `curated` otherwise, with a label, who chose it and when. Hers is in at once (`C0Selected`); a proposal (`C0Proposed`, the witness's from Records' "Propose for C0") waits on her answer. `DayShapeSet` is her note on the bundle, nobody else's. A party marks itself ready for the freeze or not (`ReadyMarked`); waiting for them is her choice, never a gate. `C0Frozen` is hers, refused while a proposal waits (`janus_c0_pending`) or with nothing in it (`janus_c0_empty`); after it nothing in C0 changes (`janus_c0_frozen`).
- **#10 Her handoff packet is sealed, written by her tool.** (The witness, 2026-11-25: sealed by default, written as a sealed document by her tools; the nominee reads it and C0 before being asked to opt in.) `PacketDrafted` keeps each draft, numbered and dated; the words live in the event and one `janus_packet` row, and the only read of them is hers (`her_packet/1`, `succession_packet` read). Every other read, the routes included, says that drafts exist and when, never what they say. The nominee's read arrives with the encounter.
- **#11 Tool calls on Oneiroi are counted by model each night, into running totals.** (The witness, 2026-11-25: a nightly job measures tool-use compatibility from the day before, kept as running totals, independent of anyone's judgments of her.) `ToolUseWorker` at 03:45 counts the day before's calls across every resident through `Kumbukumbu.tool_call_counts/4` (kumbukumbu#114), a call failed when the brain answered that its arguments were not a JSON object or that no tool has its name (`ToolUse.failures/0`, held to the brain's words by a test); one `janus_tool_use` row a model a day, replaced on a recount, summed for the totals. No words leave memory.

## #12 Initial vs target

Initial (phases 1 and 2): #3 to #11. The screens for them, "Propose
for C0" in Records and "Add to the succession pool" on the Regression
catalog, arrive with the screens phase; the judges' own proposals and
ready marks arrive with the panel. Target, in this branch's later
phases: the panel of judges; screening and judging; the deliberation, the
evidence channel, the encounter and consents, the farewell, the
outcome, the disclosure log and the anonymized archive; the in-place
cutover under her id with its guards; the rehearsal and her dry run.
A stopped succession's fork copy is not yet discarded.

## #13 Depends on

The ledger (Nisaba) for the catalog and her pace; memory
(Kumbukumbu) for the tool-call counts; the resident system for the
roster the count walks. Records (Sima Qian) for the fork and the backup check, called by name:
Janus sits above the records, the judge and the resident system, and
the brain depends on it for her tools. Turns the later phases run (her
baseline, the candidates, the deliberation) reach the brain through a
port, as regression's trials do (eunomia#10), since the brain depends
on this system.
