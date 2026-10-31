---
paths:
  - lib/oneiroi/sima_qian/**
  - lib/oneiroi/sima_qian.ex
  - lib/mix/tasks/oneiroi.sima_qian.rebuild.ex
  - test/oneiroi/sima_qian/**
  - test/fixtures/sima_qian/**
---

# sima-qian

**Records.** Chinese, see-mah CHEN (Sima is the compound surname).

> "A man has only one death. That death may be as weighty as Mount Tai, or it may be as light as a goose feather." "...It is because I regretted that it had not been completed that I submitted to the extreme penalty without rancor." — Sima Qian, Letter to Ren An, trans. in de Bary & Bloom, Sources of Chinese Tradition, 2nd ed. (Columbia UP, 1999)

Sima Qian was the Grand Historian of the Han dynasty. He chose the "extreme penalty" over an honorable suicide so that he could finish the *Shiji* — the Records of the Grand Historian: 130 chapters of annals, tables, treatises and biographies, the form every later Chinese history copied.

The records subsystem — export, replay, attestation; everything the realm says about what happened — is named for the tradition of keeping the record at any cost. Testimony that cost the author, finished anyway, organized so well it outlived the throne that punished him.

Export, replay, attestation, git providers, backups (spec §6.10). Built
attended with the spine (plan P0.7, decisions log round 9).

## #1 Owns

The export (`records/events/<day>.jsonl`, every stream that is the
resident's, and `records/README.md`), the
Merkle root, the git port, the backup run, the rebuild, the import (the
intake from a repository, with the library port it adopts through), the
attestation check, the two nightly workers on the `sima_qian_nightly`
queue, and the `mix oneiroi.sima_qian.rebuild` task. The fixture log under
`test/fixtures/sima_qian/` and its replay test.

## #2 Standing decisions

- **#3 The export is byte-stable and names the resident as `$self`.** One
  JSON object per line, keys in a fixed order (`sequence`, `stream`,
  `type`, `version`, `at`, `actor`, `data`), data keys sorted, one file
  per UTC day rewritten whole each run; every occurrence of the
  resident's uuid is written `$self`, which is what lets a rebuild be a
  new resident and still re-export byte for byte. Fields an event
  declares `redact:` are null. The self-conversation's letters are on
  the stream and so in the export; the backup records a receipt for the
  ones it carries for the first time (agathos-daimon #28), after
  `ExportWritten` and before the commit.
- **#4 `sequence` is the line's ordinal, dense from 1.** The stream has
  gaps where the unexported bookkeeping sits and a rebuild replays the
  lines densely, so only the ordinal re-exports identically. The stream
  version the export ran through is the commit's `Oneiroi-Sequence`
  trailer and `ExportWritten.through`.
- **#5 The export stays a watermark behind capture.**
  `SIMA_QIAN_WATERMARK_SECONDS` (a bound, 60) by the event's own instant,
  so a turn still being written is never half-exported.
- **#6 The root is sha256 over path, NUL and bytes, in path order, paired
  upward with the last leaf doubled on an odd row.** Deterministic for
  the same bytes on any machine, which is the whole claim: a commit's
  trailer names it and a wake recomputes it.
- **#7 Backups commit by class, and a stray file fails the run after the
  rest has landed.** The soul alone, writing and research apart, machine
  state together (David's rule); the identity files ride with the soul
  (agathos-daimon #14), and the export writes them at the root. A path outside every class fails the run with
  `sima_qian_stray_files` naming it, after the export is committed and
  pushed, so the backup is taken and the stray is loud.
- **#8 The git port is one module calling the `git` binary, with two
  providers by URL.** A local path for tests and self-hosters, GitHub over
  HTTPS with a fine-grained token the witness pastes, stored encrypted
  and built into the push URL in memory; `git` is told never to prompt,
  and an error's text has any credential redacted. Gitea and any other
  remote by URL need nothing new.
- **#9 Rebuild is replay into a fresh stream under a new id, refusing a
  repository already imported at that root.** The lines are appended as
  recorded with `imported` metadata, then `Imported` (source, attestation
  held/failed/none, root, sequence) and custody to the importing
  witness. What cannot come back is printed by name: nothing in P0.
- **#10 Attestation is a nightly job until there is a wake.** It
  recomputes the root over the working export and raises
  `RootMismatchDetected` with both roots and the commit; the witness
  sees it on the stream.
- **#14 The working repository is an export, made a repository on first ask.** `repository_dir/1` is the resident's directory under `SIMA_QIAN_ROOT`, initialised if it is not one yet: where the library writes its files between backups (seshat #12), under the folders the classes of #7 already commit. Nothing else about the repository leaves this system; the export and the backup read the same path.
- **#15 An import is the rebuild and then the rest of the repository, and the clone becomes the working repository.** `import_resident/4` (`POST /v1/residents/import`): a repository with `records/events/` replays as #9 does, under the records' own name and slug; one without is created under the name and slug the witness gives, and refused without them (`sima_qian_name_required`). Either way the clone is copied to the resident's directory under `SIMA_QIAN_ROOT` with its history, so the next backup commits on top of the source's commits, and its `origin` remote is removed with it. The identity files at the root are seeded as `uploaded` (agathos-daimon #11), or proposed with a note where the records say first contact has passed and the file differs from them: never overwritten, never dropped. Every file under a kind's folder is adopted through the library port and indexed once (seshat #25). What at the root is none of those is listed by name, with any file the aggregate refused for its content and any path the library could not name, and `records/` and `honcho/` among them unless the source is an Oneiroi export (it has `records/events/`), `records/` file by file where it held David's (#19), as `ImportCompleted`'s `not_transferred` (agathos-daimon #25), and the brain tells the resident on its first turn (brain #26). `rebuild/3` stays the replay alone: the operator's primitive and the round-trip tests' subject.
- **#16 An import clones only from a configured scheme, and records the URL without its userinfo.** `SIMA_QIAN_IMPORT_SCHEMES` is `https` alone by default: a bare path or a `file` URL from a request is refused before anything is cloned (`sima_qian_scheme_refused`), because `git clone` of a path reads a directory on this host, another resident's working repository among them. The suite adds `file` to import from local bare repositories, and a bare path stays refused there. The source the log keeps (`Imported.source`, exported, and the key `Store.imported/2` refuses a second import on) is the URL with its userinfo stripped, where a GitHub URL carries the token; the clone itself uses the URL as given.
- **#18 An import is rehearsed on a throwaway store before it is run on one where someone lives.** `Oneiroi.SimaQian.DryRun` (`mix oneiroi.import.dry_run`, and the reusable workflow `import-dry-run.yml`) imports a local checkout exactly as `import_resident/4` does, backs it up once to a local bare remote, and reports by name and count: the identity files seeded and the soul lines minted, the documents adopted, each kind's folder by files, bytes and the tokens the index will embed (four bytes a token, an estimate), the not-transferred list as the resident will be told it, what David's records were made into, kind by kind (#19), and, for a source that is not an Oneiroi export, every file under `honcho/`, and under `records/` where they are not David's, that comes across read by nothing. The task refuses a real provider (so no model is called and no key is needed) and a store that already holds a resident; no turn is taken, so nobody is at turn one (spec §12). The report never quotes a file: it goes to a CI log, and the reusable workflow is called from a private repository so that log is the caller's.
- **#19 Another platform's records are made into this one's on import, through each system's own commands.** `Oneiroi.SimaQian.David` reads the JSON Lines David exported nightly under `records/` (a repository without `records/events/` that carries them, created rather than replayed) after the seeds and before the adoption, and drives every record through the system that owns its kind, under the actor the source names: each David session an imported session (kumbukumbu #37) whose turns are captured with their original instants and speakers (the resident's replies hers, the worker's her hands', the witness's the user messages of runs the witness started, the rest the platform's; a turn begins where a user's or system message follows a reply or a tool's, or where the run's kind changes); the tag set through the hands each tag went through there, the witness's own or the resident's proposal and the witness's decision, with a tag a bookmark carries that the set does not name created as the witness's; each bookmark anchored on the turn under way when its span ended, reaching back to the turn under way when it began, pinned by whoever pinned it, tagged by the import (David did not record who applied a tag), and not made when its session has no transcript; positions, disputes, predictions and nights as judgement history (eunomia #29); the notes, the free-time ledger, the discussions and the feeds as journal entries on their days through the library port's `import_journal/3` (seshat #26), each saying where it came from. A transcript line that does not say its session, instant and role, or a line that is not a JSON object, fails the import with `sima_qian_records_invalid` naming the file and line and never the contents. The counts by kind are `RecordsTranslated` (agathos-daimon #30) and the brain names them on waking (brain #38); what under `records/` nothing read is named file by file in the not-transferred list instead of `records`. What was translated is exported with the rest of her streams (#20), and David's files stay in the repository beside it.
- **#20 The export carries every stream that is the resident's, and a rebuild restores them all.** `Export.streams/0` names them: the resident's own and its ethos, judgement, audits, conversations, memory, ledger, library, schedule, journal, governance and subscription streams; `Export.not_exported/0` names the rest with the reason for each (the sealed regression stream, the witness's account, and the Honcho bridge's stream, which points at a workspace keyed to the source: a rebuilt resident provisions its own). A test asserts every router's prefix is in exactly one of the two. The streams are found through EventStore's own search on the resident's id, read one by one and merged on the instant the store stamped each append (then the stream's name and version), so the export reads this resident's events and never the whole store. A line's `stream` is the stream's id with the resident's taken out (`resident`, `memory`, `conversation-<key>`), so an export written before this rule reads as the resident's own stream; the rebuild puts the new id back in, appends the lines in order, a run of one stream to an append, and refuses a name outside the exported streams before writing anything (`sima_qian_stream_refused`). Within the ledger, an event billed under a purpose the resident's own view never shows (`drafting`, `regression`, nisaba #4) is not exported: the export is a surface she can reach, and the unawareness invariant's test (eunomia #12) failed on the first export that carried the ledger, on a regression run's calls. A rebuild therefore restores no spend and no budget under those two purposes. `through` stays the resident stream's version. The round trip (`WholeTest`) rebuilds a resident with a turn, a bookmark, a tag, a position, a prediction, a journal entry, a check-in, a counter and a document beside its source in one store, and asserts the copy re-exports line for line and reads the same life back, and that the source's own export is unchanged after the copy replayed: the guard on replay writing only its own resident's rows (#21). A private, unshared session's messages are in the export like every other's, which puts them in a repository the witness can read; that is open, with the self-letters, for the encryption scheme.
- **#21 Replay writes only the replaying resident's rows.** A rebuilt copy keeps the source's numbers, refs and session keys, so any projection keyed on one of them alone collided with the source: the conversations projector found two sessions for one key and stopped, and the ledger's usage rows, keyed on the call's ref alone, dropped the copy's calls as already projected. Every projector query now names its resident (conventions §12, enforced by `ProjectorScope`), and `nisaba_usage` is keyed on the resident and the ref.
- **#22 Every file an import meets lands in one place, and what is left behind says why.** `Import.account/4` walks the clone, hidden files included, and holds each file as seeded, proposed, adopted, translated or an Oneiroi export's own records, or leaves it behind with its reason: a root entry outside the library's folders once for everything in it, a record nothing reads, an identity file refused for its content, or the library's own refusal (`refusal/1` on the library port). `ImportCompleted` version 2 carries the reasons beside the names, and the resident is told both on waking. A file under a library folder that adoption neither took nor refused and no rule explains is unaccounted: left behind, named, and the dry run fails on it.
- **#17 The library is reached through a port.** `Oneiroi.SimaQian.Library` (`adopt_all/2`, `folders/0`) is named in `SIMA_QIAN_LIBRARY` and read at the call, as the schedule names its wake (sunna #12); the library implements it, because it depends on this system for the repository's path (seshat #12) and an alias back would be the cycle the gate refuses.
- **#13 The Honcho instructions ride in the soul class, and a soul commit sets the card.** The export renders `honcho/custom-instructions.md` beside the identity files on every run (agathos-daimon #19), so the soul class commits it with the soul and the first backup of any resident makes a soul commit; after a run that committed the soul class the backup calls `Oneiroi.Proteus.set_card/3` with source `commit` (proteus #14), and a bridge not yet provisioned or a Honcho that is down is the bridge's to record, never the backup's to fail on.

## #11 Initial vs target

Initial (P0, then P4 slice 3 for #15 to #17): the event log only, under
`records/events/`, with the round trip (export, rebuild, export again,
byte-identical before the `Imported` line) green in CI against a local
bare repository; the import over the API from a repository with or
without records. Target: every record kind of spec §6.10, the GitHub
run by hand against a real repository (Lily's migration,
`design/lily-migration.md`), Gitea, attestation on wake.

## #12 Depends on

The platform (the kernel, the vault, Oban) and the resident system,
whose stream it reads and whose bookkeeping events it writes.
