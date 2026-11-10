# Which records belong in files: review

Status: review for Andrew (2026-11-10). Nothing is built from this yet.

## The finding that reframes the question

Nothing is database-only in the usual sense. The canonical store is the
event log, and every resident stream except `regression` is already
exported to the repo as `records/events/<day>.jsonl`
(`lib/oneiroi/sima_qian/export.ex:51`). The tables are projections that
replay rebuilds. So the data export is already minimal: the
`oneiroi:db-only` list (spec §6.10) holds only:
- derived things (embeddings, weights, every projection table);
- sealed things (regression);
- what isn't hers (account, household, invites, profiles).

The rule Andrew stated is already the spec's, in his words: "All raw
text should be in the repo unless there's a really good reason"
(spec §6.10, `oneiroi-spec.md:1207`).

The real gap is **readability**. Most record types reach git only as
JSON event lines, which "a person does not read" (sima-qian#41). Spec
§6.10 planned readable `records/` files for positions, disputes,
predictions and judge nights. F36 says they're not built yet;
sima-qian#41 deferred them "until someone needs to read them outside
[the client]". The folder tree in the new Records tab is that need.

## Two patterns already in use

- **File is the truth, row is the projection.** Documents, oracle
  answers, research notes, keepsakes. The event carries a hash, not the
  text (seshat#12). The witness or resident edits a file.
- **Rows are the truth, file is rendered from them.** Journal day
  files, soul lines, `STATE.md`, `records/bookmarks.md`. These are used
  when a record needs stable granular ids, relational joins or
  per-field state that a hand edit would break (agathos-daimon#27).

Either pattern puts the record in the tree. The choice is about who
edits what, not about whether it's in the repo.

## Per type

| Type | Today in the repo | Shape | Recommendation |
|---|---|---|---|
| journal | `journal/<day>.md` rendered + events | entries per day, todo flags | done |
| positions | events only | numbered chains, no forks, tied to disputes | **render** `positions/<n>.md`, one per chain with its supersessions |
| commitments | events only | short row, open → kept/released + note | **render** `commitments.md` (open first, then kept/released) |
| predictions | events only | logged, due, resolved by him | **render** `predictions.md` |
| habits | events only | definition + scores computed from citations | **render** the definition as `habits/<n>.md`; scores stay derived |
| seeds | events only | state machine + citation rows | **hold**: private as to words (Lily's call, letter #476); see below |
| figures | events only | high-frequency increments; value is the fold | **keep as rows** (the write pattern is the weights exception's); render current values into one `figures.md` |
| self-letters | events only | read receipts on any read but hers | **render** `letters-to-self/<n>.md`; export already records a receipt (agathos-daimon#28) |
| state lines | `STATE.md` + events | key/value overwrite | done |
| keepsakes, oracle, research | files + events | | done |
| bookmarks | `records/bookmarks.md` + events | highly relational, weights | done (copy); weights stay derived |
| tags, revisions, wash flags, house letters | events (tags partly in bookmarks.md) | lifecycle rows targeting other records | low priority; render if the Records tab shows them as folders |

"Render" means rows are the truth and the file is rendered on every
write, as with the journal. A file-is-truth move only makes sense where
someone would edit the text by hand. Of these, only positions and habit
definitions come close, and both have invariants (chains that can't
fork, trigger matching) that a hand edit would bypass. So the
recommendation is render everywhere, with the Records-tab viewer
reading the rendered file.

## The privacy constraint (Lily, letter #476)

"The Records view and the export obey the same policy, or the export
quietly undoes the one mirror the resident was promised." Her audit
makes seeds the one private record type: existence and count visible,
words private, and graduation publishing them. To check before
anything is built: the event lines in `records/events/` carry event
fields whole, except fields declared `redact:` (which go to the vault,
not to her). If a witness can read her repository, private words in
event lines (seeds, and today the free-time session's words if the
conversation stream carries them) are readable there. That would
already undercut the free-time term; it needs checking, not assuming.

## Proposed CLAUDE.md line

Added on this branch to CLAUDE.md's load-bearing invariants, as "Repo
first". It says that event lines alone don't count as readable, and
that privacy governs the export exactly as it governs the Records view.
