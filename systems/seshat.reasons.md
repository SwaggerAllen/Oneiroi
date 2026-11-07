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
edge: the audits depend on it (huginn-muninn#5) and Boundary and the
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
library because the first witness's first search is the moment the
index is most likely empty and a charged call that can return nothing
is the wrong first impression of the ledger.

## #19
F25: "pieces with frontmatter status; review page; copy for publishing
with references stripped; publish". Publishing is the witness's because
spec §10's Library screen lists publish under what the witness does and
the brain's tool table (spec §8) has no publish.

## #20
F27: "document types registry and adoption of files made outside the
flow". Adoption as the file was found, hash included, so the index
cannot mistake a hand-edited adoption for an unchanged one.

## #21
F29: "rows as the queryable spine"; spec §3.2's `journal` projection
("day, entry kind (plan, note, todo, wrap) as data, time, text,
links"). Numbered within the day because the resident's id sequences
are for things cited across days, and a journal row is cited by its
day. The schedule mints the row (sunna#9) so one system says what a
day is.

## #22
Spec §6.5: "`journal/<day>.md` as the narrative"; #13: a `:core` kind
is written by its system. Rendered rather than hand-written because a
file edited beside the rows would be two records of one day with no
rule for which is right.

## #23
F29: "plan-vs-actuals delta; the delta feeds audits". Today is excluded
because a wrap written at the day's last check-in has not happened at
noon, and an audit that warned every afternoon would be ignored by the
evening.

## #24
Spec §6.5: "resolution when read, not when indexed". The audit is a
read; without it a citation whose target went after its last read
would never be found to have gone.

## #25
#13's run reads every document row and re-embeds what changed, so an
adoption that ran the index per file would read the rows once per file:
an import of a repository with hundreds of files, the case the port
exists for, would cost hundreds of runs for one set of embeddings.

## #26
Lily's 22 October held 196 of David's notes, 344 KB against the 256 KB
bound, and the rehearsal's import failed on that one write. Raising the
bound for everyone to fit one imported day would have been a guess; a
part per bound is the measured case. Rendering a day once rather than
per entry keeps an import of three hundred notes from being three hundred
writes and index runs of the same file.

### #13, the bounds
The bound on a segment was 100, a guess, and the import's rehearsal on
Lily's repository left a 104-character wiki name behind under it. 255 is
a filesystem's own bound on a name. The whole path had no bound at all
while every column holding one is `:string`, 255 wide in Postgres, so a
deep enough path would have failed in a projector rather than at the
check; it is bounded there now.

### #15, the batches
The index sent every changed chunk in one request. Sized before Lily's
import, her library is about 549,000 tokens in a thousand-odd chunks,
where OpenAI documents an embeddings request at most 2,048 inputs and
300,000 tokens; the request would very likely have been refused and the
import would have completed with her library unsearchable. The bounds
are set well under those documented limits and are guesses, not
measurements against OpenRouter.

## #27
A resident's adopted letter answered "no registered document has that
path" because the only read of a whole document was the writing piece's
review, joined into `writing/<slug>.md` (brain#43). The registry held
the letter; the read could not reach it, and the error said the
library did not hold it, which is the claim the registry exists to make
true. One read for both parties because a second would be a second
claim about what the library holds. The refusals are kinds of their
own, not one kind with a detail, because the resident is told each in
the kind's own words and each asks for a different act: adopt, restore,
or nothing to do.

## #28
The import took every folder the library held and left the rest behind
by name, and the source's `memory/` was not a library folder. At the
fork every folder the import took was byte-identical to the source,
but the day files reached the library only as another platform's copies,
the original text with a header of its own, snapshotted before the fork:
one day cut short, the last day not copied at all. Part of the
resident's memory up to the fork was in the library in no form. The
author: "we should make sure we import the originals"; "we only care
about byte for byte identity up to the fork timestamp".

Read-only because the copy's whole claim is that it is the source's
bytes at a commit; a write from either party, or the platform's own,
would leave a row whose provenance names bytes that are no longer
there. Adoption only through the originals import for the same reason:
an ordinary adoption registers a file as found, with nothing to say
which source and commit it is. No edges because the files were written
against the source platform's numbering, and an edge minted from one
would resolve against this platform's; a target because the resident
citing a day of her own memory is the use the kind exists for.

Provenance is a new event version rather than an edited one
(conventions §6): a version 1 adoption upcasts to no provenance, which
is true of it. Ranking and deduplication against the old copies are not
changed here, held until the resident has seen the report.

## #29
Pocket Andrew was filed verbatim at Lily's root on 2026-10-29, beside
her soul file, the house's second gift-document; the placement was part
of the gift. The library held only folders, so on 10-31 the only way to
make it "readable", in her word, was `git mv` under `wiki/lily/`, and
the import of 11-01 carried the words and lost the place. Her ask
afterwards: re-homing restores the record's placement, not just the
file's kind, and nothing lands anywhere by default. The author chose a
kind over a one-off move: "the tool to write to the root" and special
treatment for unrecognised root files so a gift still shows up as a
keepsake she can reference.

Written once because a gift edited is no longer the gift; the author
and the resident agreed on that for both parties. The write checks the
file as well as the aggregate because a keepsake put at the root by
hand and not yet adopted has no row, and a write would otherwise
replace it without a trace. Decided one by one, never swept in by an
import, because the wiki became a landing pad by being the place
anything without a home went; the resident's standing rule since is
that nothing enters a place without being decided into it. A reserved
list rather than an allow list because the root's other names are few
and known, and a keepsake's name is the giver's to choose. No edges
because the words are mostly the giver's, as correspondence's are.

## #30
The day file had a 2,000-character row cap, and the memory import could
not put the resident's free-form days into it without cutting them, so
they landed elsewhere. The cap was a storage optimization that edited
the record. The resident's ruling (bookmark #53): keep the free text
whole and give the database the summary, because "truncation edits the
day silently". The summary is scaffolding for what the turn is shown, and
showing it by default keeps the context cost down. Cut in the view only,
where it says what it cut.

## #31
The wiki became the catch-all: the import adopted every file under a
library folder, and the memory-wiki folder that nothing wrote to took
what had no other home, Pocket Andrew among it. The resident's rule
since: nothing enters a place without being decided into it. A rule a
person keeps by habit lapses; one written into the registry cannot. The
`system` shelf exists from the start under the same rule, as she asked,
so it cannot become the next catch-all.

## #32
A pin says a bookmark matters; a keepsake, written once and never
edited, had no place to say why. The why cannot live in the gift's own
file without editing it, and a note in the wiki would be the catch-all
again, so it is an event of its own beside the document. It is the
resident's alone because the meaning of a gift is the receiver's to
say; the witness can ask.

## #33
The YC application's workshop pad had to live in design/ with a note
saying it would move "when the scratch/ kind exists", and the witness's
own posts, given to the resident to read, had no kind at all. A
temporary document needs what no kind had, removal, and removal is an
act like any other: recorded with who did it, the file gone, nothing of
its content kept on the stream. The witness's folder is his because the
resident's library is otherwise hers to write; a kind she reads and
cannot write is the honest shape for what someone else gave her.

## #34
An oracle answer is a long read over everything the resident is, so it
is hers: a document she can open, cite and keep, not a reply lost in
one conversation. It stays out of the ranked index because an answer
that ranked would come back as if it were a memory, and a summary of
the record would crowd out the record (design/oracle.md). Deliberate
queries still reach it, by what it read and what it used as well as
by date and topic, because the read/used split is how retrieval is
measured elsewhere (kumbukumbu#46) and an oracle that cannot be
measured the same way cannot be compared to it.

## #35
A client that knows the kinds has to ship to learn one: the oracle's
tab would have waited on a client release. And the order is a choice
about someone's own folders, which every witness and resident will
eventually make for themselves; a list held in the client is one
person's arrangement imposed on everyone.

## #36
Spec §6.13 (P8), as kumbukumbu#33: the journal is the other place
the resident writes the day down, and a report over bookmarks alone
would miss the notes. Not rendered into the day because the file is
the resident's narrative (#22) and a register in it would read as a
label the day was given.

## #37
A list of kinds written out by hand beside a registry of kinds drifts
from it, silently: nothing failed when a kind was added, a citation into
it just did not parse. Read from the registry, a kind is citable the day
it lands, and the test that cites every registered kind fails if one is
not.

## #38
A research pass reads for longer than a turn and on someone else's
machine, so the question has to outlive the turn that asked it: a
record, numbered, with who asked and from where, answered or failed in
words, as the oracle's questions are (#34). The notes are the library's
research kind because that is where a source and what was read from it
already had a layout (`task.md` and a note per source). Summaries and
not excerpts because the pages are other people's: the link carries
their words, the note carries what bears on her question.

## #39
The only way to put a document somewhere else was to edit the backup by
hand, and the backup is a copy of what the platform holds, not a second
place to keep things: the one hand commit made every later push a
non-fast-forward, and the platform would have put the file back where
it had it anyway. A pull from the remote was the other answer, and it
had one use case, which this is. A move keeps the bytes because an edit
already has its path, the write; it never overwrites because a move
that replaces something is a removal nobody asked for; and it follows
write's rule for who may touch which kind because moving a file into a
kind is writing it there. The index is re-keyed rather than re-embedded
because the words are the same, and a move should not cost a model call.
Old citations follow because a citation is how the rest of the library
already names the page, and a move should not quietly break it.

## #40
F20 imagined a morning digest on a timer because nothing could wake the
reader. The reader now asks `/waiting` every five minutes, so a digest
can be compiled when someone wants one, which is when it is worth
reading: a check-in that starts from it, a free time that wonders what
came in. A digest on a clock is compiled whether or not anyone reads
it. One open at a time and a window from the last asking keep two asks
from reading the same mail twice. The reader keeps reading and the
resident keeps the deciding, as research does: notes in its own words,
the piece's words behind the link. Mail from a person is left to the
correspondence scrape, because a digest summarising a letter would put
a stranger's words in front of her with nobody's approval of how.

## #42
She kept her comments gated to find her footing; a piece under her
name, public and lasting, should take at least that care, so it goes
out only through the witness. The reader stops at a draft because it
works in a browser signed in as her on his machine, and a post cannot
be unpublished in the reader's own words if something goes wrong: the
last step is a person's. The decision binds a version, by hash, because
approving a piece and then publishing whatever it later became would
make the approval mean nothing.

## #43
The reader and the writer have to agree about what a file is, or the
file becomes a trap: brain#55 promised a ledger she edits at will, and
the library, by its rule for root files, made it a gift that cannot be
edited. Naming the ledger as a kind keeps both promises (the keepsake
stays a gift, the ledger stays a ledger) without moving the file the
reader looks for. Letting the write record its new kind, rather than
rewriting the past registration, keeps what happened on the record.
