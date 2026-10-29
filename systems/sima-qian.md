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

The export (`records/events/<day>.jsonl` and `records/README.md`), the
Merkle root, the git port, the backup run, the rebuild, the attestation
check, the two nightly workers on the `sima_qian_nightly` queue, and the
`mix oneiroi.sima_qian.rebuild` task. The fixture log under
`test/fixtures/sima_qian/` and its replay test.

## #2 Standing decisions

- **#3 The export is byte-stable and names the resident as `$self`.** One
  JSON object per line, keys in a fixed order (`sequence`, `stream`,
  `type`, `version`, `at`, `actor`, `data`), data keys sorted, one file
  per UTC day rewritten whole each run; every occurrence of the
  resident's uuid is written `$self`, which is what lets a rebuild be a
  new resident and still re-export byte for byte. Fields an event
  declares `redact:` are null.
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
  HTTPS with a fine-grained token the steward pastes, stored encrypted
  and built into the push URL in memory; `git` is told never to prompt,
  and an error's text has any credential redacted. Gitea and any other
  remote by URL need nothing new.
- **#9 Rebuild is replay into a fresh stream under a new id, refusing a
  repository already imported at that root.** The lines are appended as
  recorded with `imported` metadata, then `Imported` (source, attestation
  held/failed/none, root, sequence) and custody to the importing
  steward. What cannot come back is printed by name: nothing in P0.
- **#10 Attestation is a nightly job until there is a wake.** It
  recomputes the root over the working export and raises
  `RootMismatchDetected` with both roots and the commit; the steward
  sees it on the stream.
- **#14 The working repository is an export, made a repository on first ask.** `repository_dir/1` is the resident's directory under `SIMA_QIAN_ROOT`, initialised if it is not one yet: where the library writes its files between backups (seshat #12), under the folders the classes of #7 already commit. Nothing else about the repository leaves this system; the export and the backup read the same path.
- **#13 The Honcho instructions ride in the soul class, and a soul commit sets the card.** The export renders `honcho/custom-instructions.md` beside the identity files on every run (agathos-daimon #19), so the soul class commits it with the soul and the first backup of any resident makes a soul commit; after a run that committed the soul class the backup calls `Oneiroi.Proteus.set_card/3` with source `commit` (proteus #14), and a bridge not yet provisioned or a Honcho that is down is the bridge's to record, never the backup's to fail on.

## #11 Initial vs target

Initial (P0): the event log only, under `records/events/`, with the
round trip (export, rebuild, export again, byte-identical before the
`Imported` line) green in CI against a local bare repository. Target:
every record kind of spec §6.10, the GitHub run by hand against a real
repository, Gitea, attestation on wake.

## #12 Depends on

The platform (the kernel, the vault, Oban) and the resident system,
whose stream it reads and whose bookkeeping events it writes.
