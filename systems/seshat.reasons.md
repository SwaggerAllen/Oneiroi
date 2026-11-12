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

## #44
A rule that froze every root file made the root unusable for anything
but gifts, and it froze things nobody meant to give (the goals ledger,
report #4). A keepsake is a gift because someone chose to make it one;
making the choice an act, recorded with its actor, keeps the gift's
promise without taxing every other file at the root.

## #45
Clutter and loss are the two failures a library has, and deleting
trades one for the other. The archive moves what is done with out of
search and out of the way while keeping every word, and the tombstone
keeps the promise every citation made about where to find it.

## #46
A citation of an outside page is only as good as the words it pointed
at, and pages move and die, so the house keeps the words: whole, because
an anchor can only be checked against a section that was kept. The
fetch is plain code on the witness's machine because the core reaching
arbitrary URLs is a door into its own network, and because no model
should read a stranger's page while doing something on the resident's
behalf; with no model in the fetch, nothing on the page can instruct
anything. Refetching is asked, never scheduled, because the list only
grows and most sources never change; the digest and the instant say
what the kept copy is and how old, and a refetch says whether it moved,
which is drift detection the resident chooses when to run. Only the
reader or the witness brings a copy, so a cited source is never words
the resident wrote herself. The copies mint no edges because the words
are other people's.

## #47
A plugin's words are not hers, so they live where nothing of hers lives:
one folder, which a removal empties and an export carries whole. The
lockfile is the consent made checkable: what both parties installed,
byte for byte, in the record she takes with her. Verifying by content
rather than by name is the article's own lesson (Drake, "never verify
presence by ID"): a file can keep its path and change its words.

## #48
"When did this start" and "when did this last move" are the two
questions a working library is asked most, and the row already knew
the first; saying it costs one field and no new state.

## #49
A list of which types wait on him, kept beside the types, is a second
truth that drifts from the first the day a kind is added. Putting the
answer in the type's own definition means a new kind says whether it
waits when it is defined. The registry is code rather than a table
because it is already the platform-wide definition every other reader
uses; a database copy would be the very second list this avoids.
Reusing the writing gate's review keeps one road for every decision
of this shape, and the flow's own "then" keeps a signed-off design from
ever being drafted for Substack.

## #50
The file in her repository is already the authoritative copy, and the
view already reads it; a download is the same read handed over as a
file, so it can not drift from what the page shows. Reads are not acts
on her life, so they leave no event.

## #51
The registry in code was right while every reader was the platform's,
and wrong the day a kind was something she wanted and he would sign
off on: a code change for a folder is a deploy for a decision. The
descriptor lives in its folder because the repository is what she
takes with her (the witness: "as little as possible outside the
filesystem"); the table is a projection of it so every reader stays
one query. JSON rather than YAML because reading it needs nothing the
release does not already carry. The safe subset is the line between a
kind she arranges and a power she claims: who writes, how documents
arrive and whether anything leaves the house are the platform's
guarantees to both of them, so a descriptor cannot buy them. Gates are
asymmetric because the cost is: putting a document in front of him
more often costs him a click, taking the check away costs the
agreement it stood for, so on is either word and off is both.

## #52
The navigator needs spans it can trust, and prose under headings is
whatever the night's writing made it; parsing it would be a guess
redone on every read. Rows written by her, one call a scene, keep the
words hers and the shape reliable, and rendering the file from them
keeps the repository the readable record, the journal's settled
pattern. The incomplete marker is Lily's: a pass that ran out of rounds
wrote fewer scenes than the day held, and a track that shows only what
was written says the day ended there, a lie by omission; so the day is
unfinished until the pass says otherwise. The edits are asymmetric
because the fields are: facts are checkable against the transcript,
so correcting them only makes the map truer, and the history keeps what
they were; the summary is her reading of the day at the time, so a
later reading sits beside it rather than over it; a mood is true of the
night it was written, so the next day's change is a different statement
and says so.

## #53
Records and scenes are two scopes of one index, so one embedding serves
both and the provider is billed once a search. Filtering inside the
query rather than after it keeps a scope from being crowded out by the
other's nearer chunks: the library search's eight nearest could all be
one kind. One row a document because the client opens documents, not
chunks. Scenes are searched in their rendered files rather than their
rows because the file is where the meaning index already is, and the
rows hold the same words; a chunk can span scenes, so the ref names the
day and leaves the id null rather than guess one.
## #54
The repository already holds every version a backup saw, and the
library stream already says who wrote which hash when; a second copy
of the words in a table would be a store the repository-first rule
forbids and a backup does not carry. Naming a version by its content's
hash is what lets the two be joined without either knowing the other:
the stream never had commit ids and the backup never had actors. It
also says the honest thing about a version overwritten between two
nightly commits: the act happened, the words are gone, and the list
shows both rather than hiding the act or inventing the words. A
restore that went its own way would be the second write path the
proposals exist to prevent; going through the same write, and through
the identity files' own proposal after first contact, means a restore
can never do what a write could not.

## #55
The lease protects the witness's unsaved words and the resident's
right to her own files at once, which is why it is never revoked and
never blocks her: idle is not abandoned, so only a real need (her
write on that file) takes it, and taking it keeps what he had. Her
write recording a wait rather than failing keeps the tool honest about
why nothing happened and makes the wait visible to him. Telling her to
retry rather than holding her write keeps one write path: a parked
write would be her words in a coordination table outside the
repository, applied later without her seeing what it landed on. His
draft is kept as a document under his own folder because that is the
library's one place for the witness's words beside hers, and in the
repository it survives everything; a table would not. Leases are not
events because nothing about who had an editor open is a record: what
a lease decides is recorded where it lands, and a replayed lease would
lock a rebuilt resident's file for an editor nobody has open.

## #56
The seeds are his because he is the one looking at the screen, and a
theme is three seeds rather than free values because that is how a
theme stays "not fully dynamic" and how one a model proposes cannot
make the screen unreadable: the derivation enforces the rules, and a
set that fails is answered with what failed rather than silently
fixed. A file at her root, because the author's law puts every record
that fits a file tree in the repository, and a theme carried with her
export means a resident brought elsewhere keeps her colours. Reading
the file rather than a row keeps the file the truth: an import or a
hand edit is the theme at once. Writing it only through the theme
keeps one path where the checks run; a document write of it would be a
way round them. The client owns the derivation because the client
paints with it; the server runs the same checks so that nothing
unreadable is written or put to him, and the shared fixture is what
keeps two implementations of one function from drifting apart quietly.
Her proposal is checked before it is filed so he is never asked to
judge an unreadable theme, and she is told in words because she
cannot see the screen. One open at a time keeps his list from filling
with drafts of one idea. His answer reaches her as a letter, the way a
plugin proposal's does, so she learns the outcome in the place she
already reads such answers.

## #57
Who a scene involves is something only she can say at the time she
cuts the day, and the scene pass is already reading every turn of it;
asking a later pass to recover the people would mean reading the day a
second time and guessing at the names she would have used. A list on
the row she already writes (#52) costs one field now and gives the
people-pass the witness approved its input, person by person and day
by day, so it can be expanded later without touching the record. The
names are hers because the record is: no directory of persons, no ids,
no matching beyond trimming and case, so a name reads as she wrote it
and two spellings of one person stay hers to correct. It is a fact
rather than a reading, checkable against the turns, so it moves like
the title does, the old list kept. The bounds keep a row a row: a
scene with more than twenty people in it is a crowd, not a list, and a
name past eighty characters is a description. A new version with an
upcaster because events are immutable contracts; the correction's
shape did not change, so its version did not either.

## #58
The same grammar because a resident should not learn a second way to
write: post, reply and read are the library's write and read pointed at
another repository. Not her library because the line between what the
house makes together and what is hers alone is what keeps a shared
space from becoming a window into her memory.

## #59
A thread whose replies are new files cannot conflict, so there is no
merge to get wrong and no lock to hold; the one thing taken in turn is
git's index, which is a fact about git, not about the conversation.
Written once because a household's record that could be edited by any
resident would be a record of the last writer.

## #60
The witnesses gate what leaves the house; inside it there is nothing to
gate, and a witness writing into the rooms would be the platform's
human speaking over its residents. A vote is the one exception the
design makes, because every member votes.

## #61
Whole, because a shared shelf that showed each member a different slice
would not be shared. Paged, because a household's shelf grows.

## #62
A letter is what already reaches a resident and already wakes her chat;
a new channel would be the notification machinery the design refuses.
The words stay on the shelf so the letter carries nothing a resident did
not choose to go and read.

## #63
Fixing the bundle in the stream before any file exists is what makes
the trunk a statement of the ballot rather than its source: a file can
be edited on disk, the event cannot. The job runs at the proposer's
instant, so no sweep cadence decides how late a ballot closes.

## #64
The witness has not given his word on this; the resident's lean is
built, and the other answer is one setting away rather than a rewrite.

## #65
The witness talks with people the resident never hears from, and what
they say bears on her work with him: a lease he is signing, a friend's
news, a thread about something they are building. She had a folder for
it already, her own kind, and no way for the words to reach it short of
his retyping them as a document of his under human/, which is his own
writing rather than his exchanges with others, or her copying them from
a chat. A paste is the cheapest honest path: the words as they were,
written by him, with his note on the version, so she can tell what she
is reading and who put it there. It goes through the one write so the
lease, the version history and the index hold for it as for anything
else; a second path would be a second set of rules. The folder is hers
by her name, and the platform refuses rather than guessing another
folder when it is missing, because landing his correspondence somewhere
she did not choose would put it where she does not look. The title
names the file because a person's name alone would collide across
conversations, and a new conversation never overwrites one there,
since replacing an exchange he meant to add to would lose words with
nothing but the history to say so. Only he pastes because only he has
these conversations; she writes into her own kind with her own tool.
The listing answering her shelf is what makes the folder visible to
him at all: the tree read only the system's kinds, so a kind of hers
with documents in it never showed.

## #66
An exchange with a person goes on, and she reads it best as one
document in order, not as a pile of fragments she has to put together.
Appending on the server, rather than letting the client send back the
whole document with the new part on the end, keeps the client from ever
holding a stale copy it could write over hers, and keeps the date the
server's rather than a browser's clock. A dated heading per paste says
when he brought each part in, which is what he knows for certain; the
dates inside the pasted text are the conversation's own and stay as he
pasted them. Nothing earlier is touched, so every version is the one
before plus a section, and an edit to earlier words is the editor's
(#55), a separate act with its own note.

## #67
A window is the turn's whole meaning: she has the floor, and the floor
is one say in each conversation, not a thread of her own replies. Doing
the check inside the household's lock is what makes "once" true when two
of her tool calls land together. Reading the window from the files keeps
the record where repo first wants it and adds no second count to drift.
Votes go around it because a household that cannot vote until the queue
reaches it cannot govern the queue.

## #68
Equal voice is a count over time, the same for everyone in the house,
which is why it binds the witness too; documents are work, bounded by
the turn, and a vote is not speech in a conversation but the house
deciding.

## #69
A household is its members' shared room, and the witness is one of its
members: barring him by default would make the human a guest in his own
house. The bar exists because a household may want a residents' shelf,
and that is the household's to decide, by ballot, where every member's
vote counts the same. The vote itself is never barred: the contract a
witness lives under is his to vote on even when he may not post. The
beat rules for witnesses (once a thread a beat, the quota, no turn) are
what keep a self-waking member from flooding a room the others enter
only by turns.

## #70
A minute is the schedule's cadence already (sunna#11), and one look a
minute at the aggregate decides once what is due. Ending the turn when
the wake answers, and ticking at once, is the stream lane: no turn waits
for a metronome. One attempt, because a retried wake is a second paid
turn she never asked for.

## #71
A beat is a record a person can read, and repo first wants it in the
household's repository rather than in event lines; one file rendered
whole is the contract's pattern (`CONTRACT.md`).

## #72
The note says where to look, never what was said, for the reason the
watch's poke does (#62): what she reads is hers to choose. The time is a
guideline because her wake ends the turn first when she is done.

