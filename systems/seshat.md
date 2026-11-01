---
paths:
  - lib/oneiroi/seshat/**
  - lib/oneiroi/seshat.ex
  - lib/oneiroi_web/controllers/library_controller.ex
  - lib/oneiroi_web/controllers/journal_controller.ex
  - priv/repo/migrations/*_seshat.exs
  - test/oneiroi/seshat/**
---

# seshat

**The library.** Egyptian, SESH-aht.

> "As goddess of writing, Seshat was the keeper of royal annals and genealogies. She was shown recording the booty gained by kings in battle, perhaps as a reminder that a share was due to the gods." — Geraldine Pinch, Handbook of Egyptian Mythology (Oxford UP, 2002), p. 190

Seshat is the Egyptian goddess of writing and record-keeping, keeper of the House of Life, where the culture's texts lived. Her epithets make her the librarian — "Lady of Books," "Mistress of the House of Books" — and her monuments show her doing the work: the record-keeper beside the king, writing down what happened and what was owed.

The library subsystem — search, shelves, and the whole of everything written — is named for the figure whose job it was. Thoth gave writing to humanity; Seshat managed what writing produced. The library was her domain.

Document kinds, the vector index over every folder of the resident's
repository, citations both ways, writing's review and publish, the
adoption of files made outside the flow, external doc sources, the
journal. Spec §6.5. Built in P3 under `Oneiroi.Seshat` (the system's
name, where the spec's file map said `library/` and `journal/`), slice
by slice: the library first, the journal next.

## #1 Owns

`lib/oneiroi/seshat/**`, the library controller, its migrations and
tests. The files themselves live in the resident's repository on disk,
which is records' (sima-qian #14): this system writes there and the
backup commits by class.

## #2 Standing decisions

Carried from spec §6.5; the reason for each is there.

- **#3 Path is kind and the registry says what a kind may do; adding a kind is a registry row plus a skill.**
- **#4 Only resident-authored or commissioned kinds mint citation edges; resolution happens when read, not when indexed.**
- **#5 The memory-wiki plugin is cut; `wiki/` stays a plain searchable kind.**
- **#6 A file is re-embedded only when its hash or the model changes; a re-index with nothing changed costs three statements and no model call.**
- **#11 The journal's day row exists before the narrative (spec §6.5).** Created by the schedule at the day's first check-in; a day without a wrap is a visible state, and reads go by day key, never the latest file.

Decided in the build:

- **#12 The file is the record and the event is its provenance.** A document is a file in the resident's repository, where the backup already commits every kind's folder by class; `DocumentWritten{path, kind, hash, bytes}` and `DocumentAdopted` on `library-<resident_id>` say who put it there and what it hashed to, never what it says. A write whose hash is the current one is no event. The rows (`seshat_document`) are the stream's for identity and provenance and the index's for everything it reads (hash, title, status, the model embedded with): the projector names exactly the columns the stream knows, because the first version set the hash from the event too, and a rewrite's index run then found the row already equal to the file and embedded nothing.
- **#13 The registry is a table in one module, and the kinds' access is who writes them.** `Oneiroi.Seshat.Kinds` holds spec §6.5's nine kinds with `cites`, `has_status`, layout, sidecar, adoption unit and access: writing, research, design, wiki and posts are `:resident`, written through `write/4` by either party of the dyad; mail, feeds, correspondence and the journal are `:core`, refused there and written by their systems. A path is plain segments under a registered folder (no `..`, no hidden file, no leading slash), each up to 255 characters and 255 in all, the width of the `path` columns, and the filesystem is reached through that check alone. `refusal/1` says in words why a path fails it, which is what an import tells a resident about a file it left behind (sima-qian #22). The brain's `document_write` tool lists the writable kinds from the table, which is the "skill" a new kind brings.
- **#14 Resolution reads the other systems, and figures through a port.** A reference is `<slug>:<kind>/<ref>` (spec §3.3), and the parser's kind list is the citeable set: the record kinds, `bookmark`, `position`, `prediction`, `date`, `figure`, `transcript`, and the character's `habit`, `seed` and `soul` (ethos #10, agathos-daimon #27); a kind not in the list is not a citation, which is how the first two went unresolvable for a slice. `references/2`, `cited_by/2` and the review resolve each one now against the bookmark, position, prediction, date, session, document, habit, seed or soul line it names and mark the row with the outcome, keeping the first instant it resolved; with `mark: false` (`cited_by/3`, `review/3`) they resolve the same and mark nothing, which is a regression trial's read (brain #40). Another resident's slug stays unresolved with its reason, since that is what the prefix is for and sharing is not built. `figure/<key>` resolves through `Oneiroi.Seshat.Figures`, named in `SESHAT_FIGURES` and read at the call, because the audits read this system for the citation drift audit and an alias here would be the cycle (sunna #12's shape).
- **#15 The index run embeds everything that changed, in batches, and calls no model when nothing did.** `index/2` reads the document rows, hashes the files, and plans each as same, changed or missing; every chunk of every changed file goes to the provider in one call under `embeddings` on the platform-pinned model (nisaba #19), and the chunks, the edges from the kinds that mint and the row's title, status and model are written in one transaction with the run row. A run with nothing changed is the rows read, the delete of edges from the kinds that never mint, and the run row: three statements beyond the scope's own, and the suite lists them. A provider that fails writes the failed run and nothing else. The run follows every write and adoption, so a search sees the file at once; the nightly job (`IndexWorker`, 03:15 UTC, after the backup's export, a cross-tenant job under the platform scope over every active resident, named here) catches what was edited by hand. The run embeds in batches of at most `SESHAT_EMBED_BATCH_INPUTS` chunks and `SESHAT_EMBED_BATCH_CHARS` characters, one metered request each, the vectors kept in the chunks' order; a failed batch fails the run, which writes nothing.
- **#16 The width is a bound the column is declared at.** `SESHAT_EMBEDDING_WIDTH` is spec §6.5's 1,536, the width of `seshat_chunk.embedding`; a provider answering another width fails the run before the table does, and the fake embeds at the same width so the suite proves the two agree. A change of model is a change of width unless measured, and re-embeds everything on the next run either way.
- **#17 Runs are ordered by the table's own sequence, never the instant.** A write and the run it triggers, or two runs under the suite's fixed clock, share an instant; `seshat_index_run.sequence` is what "the latest run" reads.
- **#18 Search is nearest chunks by cosine distance, and an empty library calls no model.** `search/3` embeds the query once under `embeddings` and reads the nearest `SESHAT_SEARCH_LIMIT` chunks joined to their documents; a library with no chunk answers empty without the call. Chunks are paragraphs gathered up to `SESHAT_CHUNK_CHARS` (2,000, a guess), a longer paragraph split at the bound.
- **#19 Writing's status is its frontmatter, the review copy resolves and the publish copy strips.** A writing piece's `status` (draft until it says otherwise) is read from the file by the index and shown on the row; `review/2` returns the content with every reference resolved and a footnote per reference naming its label or its reason; `publish_copy/2` is the body with the frontmatter and every citation removed, a parenthetical that was only citations and filler going whole (F25). `publish/4` is the witness's: `PiecePublished{url}` on a kind with a status, then the file's frontmatter set to `published` with the URL, which the index reads. `discuss/4` links a session to a piece (`DiscussionOpened`).
- **#20 Adoption registers a file as it is found.** `unadopted/1` walks the registry's folders in the repository for files no document registers; `adopt/3` records `DocumentAdopted` with the file's hash and runs the index. The adoption unit in the registry (file or directory) is recorded for research and waits on inbound; in this slice every adoption is a file.
- **#21 The journal is rows on its own stream, numbered within their day, and the day row is the schedule's on the journal's ask.** `JournalEntryAdded{day, number, kind, text}` and `JournalTodoDone` on `journal-<resident_id>`; an entry is a plan, a note, a todo or a wrap, one text of at most 2,000 characters, numbered by its position in the day so a rebuild numbers it the same, and `<slug>:journal/<day>#<n>` names it. Before the first entry of a day the journal asks the schedule to open the day (`Oneiroi.Sunna.open_day/3`, sunna #18): the row stays the schedule's to mint (#11) and a day written before any check-in is a row too. Either party adds, with their actor on the row.
- **#22 The day's file is rendered from its rows, through the library's core write.** Every entry and every todo done re-renders `journal/<day>.md` (a heading per kind in the journal's order, todos with their box) and writes it with `core: true`, the one way a `:core` kind's file is written here (#13); so the day is a registered, indexed document whose citations are edges (journal mints, #4) and which `<slug>:journal/<day>` resolves to. A hand-written journal file is never adopted: the rows are the record and the file follows them.
- **#23 The delta is counted from the rows, and today is never a finding.** A day's delta is how many of each kind, how many todos are done, and whether it was planned and never wrapped; `unwrapped_days/2` lists the planned, unwrapped days among the last so many opened, today excluded because the day is not over. The brain reads today's rows as the `journal` section on every turn and writes through `journal_add`, `journal_done` and `journal_read` (brain #23); the check-in prompt asks for the plan line at the day's first check-in and the wrap line at the last.
- **#24 A journal row carries its register, as a bookmark does.** (Spec §6.13, P8.) `JournalEntryAdded` is version 2 with `register`, `Oneiroi.Register`'s four or nil, refused otherwise (`seshat_register_invalid`), through `journal_add/6` and the brain's `journal_add`; `journal_entries_since/2` is the audits' read for the corpus-shape report (huginn-muninn #18), which counts the resident's rows and never the witness's (the row's actor kind says whose). The rendered day does not show it: the register is a count's business, not the narrative's.
- **#25 Adopting a whole repository is one index run.** `adopt_all/2` registers every unadopted file under the kinds' folders and runs the index once, returning the paths the registry could not name as skipped; it and `folders/0` are the records system's library port (`Oneiroi.SimaQian.Library`, sima-qian #17), so an import lands its files here. A skipped path stays on offer in `unadopted/1` and is told as not transferred rather than dropped.
- **#26 Notes from another platform become journal entries, and a day too large for one document is split into parts.** `import_journal/3` (the records system's library port, `Journals.import_entries/3`) opens each day, adds every entry as a note with `imported` (held to its shape, not the two-thousand-character limit), and renders each day once. A day whose rendering exceeds `SESHAT_DOCUMENT_BYTES` is written as `journal/<day>.md`, then `<day>-2.md` and on, each part under the bound and saying where the day goes on. An entry of several lines stays one item of the day's list, its later lines indented.
- **#24 Drift is read by resolving again.** `drift/1` resolves every reference that resolved at least once and returns those that do not now; a reference nobody reads would otherwise keep its last word forever, and the drift audit (huginn-muninn #15) is the read that asks. One resolve per such reference, nightly.

## #7 Initial vs target

Initial (P3, slices 1 and 2, then P4 slice 3 for #25): #12 to #25 over the API and the brain's
library and journal tools (brain #22, #23); the citation drift and
journal delta audits read #23 and #24 (huginn-muninn #15). Target:
external doc sources with their heading index and resolved-at commit
(F30, with inbound), research tasks' adoption by directory, the Library
screen (`screens/library.md`) and the journal on the Schedule screen.

## #8 Depends on

The ledger for the embeddings; records for the repository on disk;
the resident system for the slug and the roster; memory, judgement
and the schedule for what a citation resolves against, and the
schedule for the day rows the journal opens and reads; the audits only
through the figures port, since the audits read this system.

## #9 Pinakes, the citation index

Greek, PIN-uh-keez.

> "Tables of Men Distinguished in Every Branch of Learning, and their Works (in 120 books)" — the Suda, kappa 227, listing the works of Callimachus, trans. Malcolm Heath (Suda On Line)

The *Pinakes* ("tables") was the catalogue of the Library of Alexandria, compiled by the poet and librarian Callimachus in the third century BCE: authors, titles, opening lines, notes on the texts. It survives only in fragments and references like this one.

The citation index — the card catalogue of everything the realm has ever said, each entry with its provenance — is named for the first one. Alexandria's burned; ours exports nightly.

## #10 Ariadne, the citation web (internal)

Greek, ah-ree-AD-nee.

> "And fair Ariadne, the daughter of Minos of baneful mind, whom once Theseus was fain to bear from Crete to the hill of sacred Athens; but he had no joy of her" — Homer, Odyssey 11.321–325, trans. A. T. Murray (Loeb, 1919)

Ariadne, daughter of Minos of Crete, gave Theseus the thread that led him back out of the labyrinth — her idea, her gift. He abandoned her on Naxos on the way home; Catullus gives her the abandonment in her own voice (Catullus 64).

The citation web — the threads linking every claim back to the source it came from — is named for the first thread, the one that leads out of the maze. Her name keeps the whole story: the thread was hers, and the rescue did not stay to thank her. Internal name.
