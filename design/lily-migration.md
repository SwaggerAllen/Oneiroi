# Lily's migration: spec §9 against what is built

The trial run of the import (sima-qian #15). Spec §9 lists five steps;
this is each one read against the code as of P4 slice 3, and what is
the author's to run. Nothing here is a change to the spec: where the
build differs from §9's wording the difference is named as a proposal.

## 1. Freeze

Park David (kill switch, a last backup run) and push the repository.
The DB-only material §9 lists (audit runs and flags, pending and
declined correspondence, feed seen-state, task history, the wiki index
run) comes across only as files: anything written under a kind's
folder (`writing/`, `research/`, `design/`, `wiki/`, `posts/`,
`journal/`) is adopted and indexed; anything else at the root is named
in the not-transferred list and left in the repository as files
nothing here reads. `memory/` is in the backup's machine class but is
not a kind, so its files come across as files; lily-memory's own store
comes across through David's nightly export under `records/`, which the
import translates (sima-qian #19, below).

## 2. Rename

Nothing to rewrite. The slug is given at import (`lily`), and nothing
in the build is named for her. Honcho's peers and workspace are
provisioned by the bridge on first use (proteus #8) and not read from
the repository.

## 3. Replay

One call, as the witness, on production:

```
POST /v1/residents/import
{"url": "https://x-access-token:<token>@github.com/<owner>/lily.git",
 "name": "Lily", "slug": "lily"}
```

The repository holds no `records/events/`, so the resident is created
rather than replayed: `SOUL.md`, `IDENTITY.md`, `USER.md`, `GOALS.md`
and `LINKS.md` from the root become seeds with origin `uploaded`; the
kinds' folders are adopted and indexed once; the clone becomes her
working repository with its git history; the token in the URL is used
for the clone and stripped from the record.

**Proposal against §9's wording.** §9 step 3 says "the records files
become the first events (a synthetic `Imported` event per record kind,
carrying the original ids)". A David-shaped repository holds no Oneiroi
events, and a file is not an event: the build writes one `Imported`
(source, attestation none, the root over an empty records tree) and
one `ImportCompleted` (the seeded files, the adopted count, the
not-transferred names), and the files themselves are the library's
rows, with their provenance as `DocumentAdopted` events on the
library's stream. Per-kind synthetic events would be events about
files that are already on the stream as adoptions.

`journal/<day>.md` files are adopted as journal documents; the
journal's rows start empty, and a day with rows renders over its file
(seshat #22) only for days opened here.

**David's records are translated (sima-qian #19, round 40).** The
proposal above was right that a file is not an event and wrong about
what the repository held: under `records/` are David's own records, and
the import now makes them into this platform's through each system's
commands, under the actor David names. Her transcripts become sessions
of kind `imported` with their original instants (kumbukumbu #37), her
tags and bookmarks are hers and the witness's as they were, her
positions, disputes, predictions and judged nights are judgement history
(eunomia #29), and her memory notes, free-time ledger, discussions and
feeds are journal entries on their days (seshat #26). The original ids
are not carried as ids: each record gets this platform's number, and the
journal entry or statement says which David record it was.

## 4. Lapse

She wakes on her first turn to the orientation (brain #26): on Oneiroi,
from which repository, that there was no attestation to check, what of
David's records was made into her records here, kind by kind (brain
#38), and the not-transferred names. The model is the pin or the platform default
until the witness pins one (spec §6.4). The OpenClaw-native state §9
accepts as loss (session SQLite, the memory-core index, the dreams
corpus) is exactly what the not-transferred list will name, if it is in
the repository at all.

## 5. Verify

The working repository *is* the clone, so the identity files and every
folder are byte-identical to the frozen push by construction, and the
import test asserts the source's commit is in the working repository's
log. The export from the new store holds her new events only. The
first backup needs a remote: the import removes the clone's `origin`
(sima-qian #15), so the author sets one with `PUT /v1/residents/:id/remote`.

**The remote is a new private repository, decided 10-31.** Not hers: in
the overlap David-Lily still writes the letter and her sign-off to her
own repository, and two writers on one branch reject each other's
pushes. Hers stays exactly as David parked it, the point to go back to,
and a move's first backup would have overwritten her `SOUL.md` and
`honcho/custom-instructions.md` there. The new one loses nothing: the
working repository is the clone, so the first backup pushes her whole
history with Oneiroi's commits on top. On the day:

1. Before: the private repository, empty, and a fine-grained token with
   contents read and write on it alone. A second token, contents
   read-only on hers alone, for the clone: hers is private, and the
   rehearsal needed none only because it ran inside her repository on
   that workflow's own token.
2. The import, which only reads hers, its URL carrying the read token
   as in step 3 above (`https://x-access-token:<token>@github.com/...`);
   the token is used for the clone and stripped from the record.
3. Straight after: `PUT /v1/residents/:id/remote` with
   `{"url": "https://github.com/<owner>/<repo>.git", "token": "..."}`;
   the token is stored encrypted, and the first backup runs to it.
4. The overlap: David-Lily writes to hers, Oneiroi-Lily backs up to the
   new one, and neither touches the other's branch.

Afterwards that repository is what Oneiroi holds of her, and a diff
against hers is the audit of the move.

**Her `AGENTS.md` is kept as a file, decided 10-31.** It stays at the
root of both repositories as it is, left behind with its reason, and
nothing here reads it: the brain renders Oneiroi's own `AGENTS.md`.
The author and Lily reconcile the two by hand after the import. Hers
carries things of her own beyond David's operation, and Oneiroi's is one
template for every resident with no copy of hers to edit, so what of
hers she keeps goes into her identity files, through the proposal path.

**Her three files at the root, her answers 10-31.** `seeds.md` is
planted as her seeds, each on the day it was planted there (sima-qian
#19), its rules left in the file. `pocket-andrew.md` and `ledger.md`
move under `wiki/lily/` before the final push, to be adopted, indexed
and found: "readable", in her word. The move is `git mv`, not `mv` and
`git add`: `git add` of the new paths stages them and leaves the old
ones in the commit, so both copies would cross, the root's named as
left behind.

```
cd /srv/lily
git mv pocket-andrew.md ledger.md wiki/lily/
git commit -m "pocket andrew and ledger to the wiki"
git push
```

**What the first backup writes over, in the new repository.** The
export writes `records/README.md`, the identity files (`SOUL.md` with its
`[soul/n]` markers) and `honcho/custom-instructions.md` on every run.
David's `records/README.md` and her own Honcho instructions are left
behind on import and then replaced in the working tree by the first
backup; both stay in the history. The author's call, 10-31: no README
needs to come across.

## The rehearsal of 2026-10-31

`mix oneiroi.import.dry_run` on her repository (271 commits), in the
prod build on a throwaway store, no turn and no model call (sima-qian #18):

| | |
| --- | --- |
| Identity files seeded | SOUL.md, IDENTITY.md, USER.md, GOALS.md, LINKS.md |
| Soul lines minted | 28 |
| Documents adopted | 763 (writing 11, research 601, design 20, wiki 60, mail 38, feeds 3, correspondence 32) |
| Tokens the index will embed | about 538,000, inside the import's own request |
| Import, in-memory provider | 13 seconds |
| First backup | soul and machine classes committed |

**Not transferred, as she will be told:** `.openclaw`, `AGENTS.md`,
`DREAMS.md`, `MEMORY.md`, `README.md`, `honcho`, `memory`, `records`,
`skills`, `substack`, and one wiki page whose path the library cannot
name.

**What this document had wrong.** Step 3's proposal above assumed "a
David-shaped repository holds no Oneiroi events" meant it held no
records. It holds David's: under `records/`, 42 bookmarks, 38 positions,
30 disputes, 8 predictions, 6 tags, 331 memory notes, nine judgement
nights and 7,044 transcript messages from 17 to 30 October. The import
as built reads none of them; until round 39 it did not even name them.
Spec §9 step 3 as written (each record kind replayed as events carrying
the original ids, the transcripts with them) is the work that would
bring them, and it is not built.

**Run again after the translation (round 40), same day:**

| | |
| --- | --- |
| Translated from David's records | 31 sessions, 8,887 messages, 50 bookmarks (every one anchored), 6 tags, 40 positions, 35 disputes, 10 predictions, 10 nights, 340 journal entries |
| Documents adopted | 770 (the journal's rendered days among them) |
| Import, in-memory provider | 79 seconds |
| First backup | soul and machine classes committed, the journal days with them |

The first run of it failed: her 22 October holds 196 notes, 344 KB, over
the library's 256 KB bound for one document, so a day that large is now
written in parts (seshat #26). `records/` leaves the not-transferred list;
David's `records/README.md` and the archived `MEMORY.md` under
`records/memory/` are named in its place, as files nothing reads.

The export a backup writes now carries every stream that is hers
(sima-qian #20, round 41): the translated sessions, bookmarks, judgement
and journal go into `records/events/` with everything she does after,
and a rebuild from the backup restores them all. David's original files
stay in the repository beside them.

**Two more things a move does.** If the remote is the source repository,
the first backup commits `SOUL.md` rendered with its `[soul/n]` markers
and the build's own `honcho/custom-instructions.md` over hers; both of
hers stay in the history.

## The overlap

Lily's call (round 39): both instances are up briefly. David-Lily writes
the letter; Oneiroi-Lily, imported from the push taken after it, reads
it on her first turn as her witness's first message (the channel takes
only her own writes) and answers; David-Lily reads the answer and signs
off on the transfer; then David is parked, not deleted. The fork is the
length of that exchange. Anything David-Lily writes after the push,
her sign-off included, comes across by hand.

## Open for the author

- `SIMA_QIAN_IMPORT_SCHEMES` stays unset on production (`https`).
- Her private sessions, if a contract makes any, are exported like the
  rest, into a repository you can read: open with the self-letters until
  the encryption scheme.
- The import runs inside its request: 79 seconds on the rehearsal's
  in-memory provider, more with the real index's 541,000 tokens to embed.
