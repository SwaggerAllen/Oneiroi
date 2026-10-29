# seshat: reasons

## #11
Spec §6.5 and sunna#9: the day is the schedule's unit, so the schedule mints it; the narrative is the resident's and may be late or missing, and the row is what says so.

## #12
Spec §3.2's store table: files in the repo, git; derived indexes are
"an index run over files and projections", neither store nor event. The
event carries the hash and not the content because the content is
already a committed file and the log would hold every version twice.
The hash column being the index's, not the stream's, is the defect the
suite found: a rewrite that embedded nothing.

## #13
Spec §6.5: "path is kind, registry says what a kind may do (document-
kinds audit)"; conventions §11: "a document's kind comes from its path,
never its content". Access per kind is the same rule from the writing
side: mail, feeds and correspondence are inbound's to write (spec §6.6),
the journal is the journal's.

## #14
Spec §6.5: "resolution when read, not when indexed; a reference that
does not resolve is kept and says why"; §3.3: "the slug prefix is the
resident's and is what makes document sharing between residents
resolvable later". The port is sunna#12's reason at this system's
edge: the audits depend on it (huginn-muninn #5) and Boundary and the
cycles gate reject the return edge.

## #15
Spec §6.5: "a file is re-embedded only when its hash or the model
changes; a re-index with nothing changed costs three statements and no
model call"; CLAUDE.md: a test that seeds three rows cannot see a
cost, so the statements are listed, not counted. One provider call per
run because every call is a ledger record and a chunk per call would
make the ledger the size of the library.

## #16
Spec §6.5: "model pinned platform-wide (1,536 wide today)". A width is
a property of the model and the column at once, so it is one setting
with the column declared from it.

## #17
CLAUDE.md's rows-keyed-on-instants lesson (huginn-muninn's increment
rows): two runs in one microsecond were one row with the newest unread.

## #18
F26: "one vector index over all folders". No model call for an empty
library because the first steward's first search is the moment the
index is most likely empty and a charged call that can return nothing
is the wrong first impression of the ledger.

## #19
F25: "pieces with frontmatter status; review page; copy for publishing
with references stripped; publish". Publishing is the steward's because
spec §10's Library screen lists publish under what the steward does and
the brain's tool table (spec §8) has no publish.

## #20
F27: "document types registry and adoption of files made outside the
flow". Adoption as the file was found, hash included, so the index
cannot mistake a hand-edited adoption for an unchanged one.
