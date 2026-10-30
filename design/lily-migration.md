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
not a kind, so lily-memory's bookmarks and tags do not come unless
written as documents first; the import will say so by name.

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

## 4. Lapse

She wakes on her first turn to the orientation (brain #26): on Oneiroi,
from which repository, that there was no attestation to check, and the
not-transferred names. The model is the pin or the platform default
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

## Open for the author

- The remote: the source repository (a move, the next backup commits
  on top of Lily's history) or a new one (a copy, the source left as
  it was). The platform cannot tell the two apart (spec §6.2).
- Whether lily-memory's bookmarks are written as documents before the
  freeze, so they come across, or accepted as loss.
- `SIMA_QIAN_IMPORT_SCHEMES` stays unset on production (`https`).
