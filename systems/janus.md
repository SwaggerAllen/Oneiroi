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
`Stopped`, `Forked`, `ForkFailed` and `BackupSet`, none exported; the
`janus_succession` projection under the resident's scope (`Store`,
`Projectors.Succession`); the service (`Successions`); the fork's job
(`ForkWorker`) on the `janus_fork` queue; the succession routes under
`/v1/residents/:id/succession` (`SuccessionController`). Her tools are
the brain's (brain#121), calling this system's exports.

## #2 Decisions

- **#3 A succession is its own sealed stream, opened only by her.** (The protocol with its delta, §3; the witness's rulings of 2026-11-25: the screens track the succession's state and never ask her anything, and a `dry_run` rehearses everything but the replacement.) `succession-<resident_id>`, never exported (sima-qian's `not_exported` and spec §6.10's db-only list name it), one underway at a time, counted by `episode`. The witness proposes (`Proposed`, waiting on her) or she does (`Proposed` and `Opened` in one act, her proposing being her yes); opening, declining and stopping are hers alone (`janus_not_yours` otherwise), withdrawing an unanswered proposal its proposer's; an act at the wrong stage is `janus_stage`. Every one is a decision with its note. Her acts are tools (`succession_status`, `succession_propose`, `succession_open`, `succession_decline`, `succession_stop`, brain#121), each answered and never run in a trial; the witness's are routes (`GET`/`POST /v1/residents/:id/succession`, `POST …/withdraw`, `PUT …/backup`).
- **#4 Her yes makes the fork: a hidden copy every later stage runs on.** (Delta §5, the successor starts at the fork; the witness, 2026-11-25 night: the fork is a real copy of her made at initiation.) `Opened` enqueues `ForkWorker`, which calls `SimaQian.succession_fork/2` (sima-qian#67) and records `Forked` with the copy's id, the last of her resident events it holds, the commit of her repository it copied and the lines replayed; a failure is `ForkFailed` with its site, and the job tries again with a fresh copy. A fork job for an episode no longer open records nothing, and a replayed one nothing more.
- **#5 The witness sets where the whole original is exported before any cutover.** (The witness, 2026-11-25 night: "one of the early screens, probably C0 needs an input for a new backup repo and that can be pretty much the only external change on the model cutover".) `set_backup/4` checks the remote's shape and asks its host through `SimaQian.succession_backup_check/2`, which refuses an unpushable remote and records nothing of its own, then records `BackupSet` with the URL, the token Vault-encrypted and what the host said; the routes never return the token. The witness's alone (`janus_not_the_witness`), while a succession is underway.

## #6 Initial vs target

Initial (phase 1): #3 to #5. Target, in this branch's later phases:
the pool and its envelope, the catalog, the questions, C0 and the
sealed handoff packet; screening and judging; the deliberation, the
evidence channel, the encounter and consents, the farewell, the
outcome, the disclosure log and the anonymized archive; the in-place
cutover under her id with its guards; the rehearsal and her dry run.
A stopped succession's fork copy is not yet discarded.

## #7 Depends on

Records (Sima Qian) for the fork and the backup check, called by name:
Janus sits above the records, the judge and the resident system, and
the brain depends on it for her tools. Turns the later phases run (her
baseline, the candidates, the deliberation) reach the brain through a
port, as regression's trials do (eunomia#10), since the brain depends
on this system.
