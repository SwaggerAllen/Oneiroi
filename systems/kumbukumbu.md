---
paths:
  - lib/oneiroi/kumbukumbu/**
  - lib/oneiroi/kumbukumbu.ex
  - lib/oneiroi_web/controllers/conversation_controller.ex
  - lib/oneiroi_web/controllers/memory_controller.ex
  - priv/repo/migrations/*_kumbukumbu.exs
  - test/oneiroi/kumbukumbu/**
---

# kumbukumbu

**Memory.** Swahili, koom-boo-KOOM-boo.

> "1 remembrance, memory, mind, anniversary; souvenir. 2 records, minutes (of a meeting/conference): ~ za kihistoria annals" — TUKI Swahili–English Dictionary (Univ. of Dar es Salaam), entry kumbukumbu

In Swahili, *kumbukumbu* names the act of keeping: remembrance, commemoration, the anniversary — and "minutes," the written record of what a meeting said.

The memory subsystem is named for what it does rather than what it stores: it remembers, commemorates, and keeps the minutes. Remembering is something you do for someone; storage is something you do to something. That difference is the design.

Transcripts, bookmarks, tags, search, weighting, the memory agent's
record. Spec §6.3. Transcripts (P1, slice 2), then bookmarks, tags,
taggings, the index and compaction (slice 3), then the behaviours
(slice 4, #13) are built; weighting and revision are this doc's file map
and the standing decisions the spec records, so a pass reaching for
them finds a record rather than a gap.

## #1 Owns

The conversation aggregate on `conversation-<resident_id>-<session_key>`
and its v1 events (`SessionOpened`, `TurnStarted`, `TurnCaptured`,
`ContextAssembled`, `Compacted`, `CaptureFailed`,
`CaptureFailureResolved`, `SessionShared`); the memory aggregate on
`memory-<resident_id>` and its v1 events (`BookmarkAdded`,
`BookmarkExtended`, `BookmarkPinned`, `BookmarkUnpinned`,
`BookmarkProposed`, `BookmarkProposalDeclined`, `TagProposed`,
`TagApproved`, `TagRejected`, `TagCreated`, `TagRetired`, `TagApplied`,
`TaggingRemoved`); the `kumbukumbu_session`, `kumbukumbu_message`,
`kumbukumbu_capture_failure` and `kumbukumbu_context_injection`
projections, scoped by the resident and by the account party to the
session, and the `kumbukumbu_bookmark`, `kumbukumbu_bookmark_proposal`,
`kumbukumbu_tag` and `kumbukumbu_tagging` projections under the
resident's scope; the index builder (`Oneiroi.Kumbukumbu.Index`); the
session, transcript, search, capture-failure, injection and adapter
capture routes, and the bookmark, proposal, tag and tagging routes,
under `/v1/residents/:id`.

## #2 Standing decisions

Carried from spec §6.3; the reason for each is there.

- **#3 Capture is full and idempotent and loud on failure; bookmarks are the resident's words and the witness never edits them; pins take at most half the budget; tags are a closed set the witness decides; the index says how many were left out.**
- **#4 A bookmark is a moment with a span, grown later by an event rather than a second bookmark; one kind of bookmark.**
- **#5 Tags cut across every record kind; a frontmatter tag outside the closed set is reported, never stored.**
- **#6 The witness pins and may propose a bookmark, and never authors one: the index is injected into the resident's context every turn.**
- **#7 Visibility is the RLS policy on `message` and `session`: a party to the conversation and the current witness read it; the export wall is what a custody transfer reveals or locks; solo sessions are readable by the witness by default and private only by a contract term.**
- **#10 Behaviours are rows the resident owns, with a trigger, a stance and tagged enactments (spec §6.3, F55).** Two scores kept apart: habit strength, a decayed measurement; connection strength, a decision trace of pins and affirmations. The brain self-tags enactments; the nightly memory pass only proposes.
- **#11 Retrieval is this system's and choice is the brain's.** Context assembly matches a closed set of situation tags against triggers with no model call and injects the matching behaviours with their enacting turns cited; whether to enact is the brain's thinking.
- **#12 Dates, figures and behaviours are tagging targets** beside the kinds a tagging already names, so the project view reaches them and no edge table is needed.

- **#14 One stream per session, and the idempotency key is the content's.** A session's turns live on `conversation-<resident_id>-<session_key>`, as spec §3.1 draws it; the aggregate keeps the keys `(started_at, hash of the messages' hashes)` of the turns it holds and a capture whose key it holds writes nothing, so an adapter that spools and retries sends a turn twice and the log holds it once (spec §8). A different `turn_ref` does not make a different turn.
- **#15 The visibility rule is the row policy.** Every projection here is scoped both ways: `resident_id`, and `account_id` the account party to the session, which for a solo session is the witness's. A witness's reads run under their account's scope and see what they were party to; the brain's run under the resident's and see everything; after a custody transfer the new witness is party to nothing that came before, which is the export wall (spec §6.12).
- **#16 A capture failure is a row until retried or marked lost, and the resolution carries a note.** The brain writes one when the provider failed and nothing was captured; an adapter writes one when it could not deliver a turn whole. The witness resolves it from the transcript screen; `CaptureFailureResolved` is a decision event.
- **#17 Transcript search is unweighted and substring**, as spec §6.3 asks of search; the FTS index of David's `message` table is a later measurement, not a line to add now.
- **#18 A transcript is ordered by the store's event number and the message's position in its turn, never by `sent_at`.** `sent_at` is what the adapter or the brain said, and two messages of one turn, or two turns under a fixed clock, share it; the projector writes `sequence` from the event's `event_number` and `position` from the message's index, and every read orders by the pair.
- **#19 Bookmarks, tags and taggings have their own stream, `memory-<resident_id>`, and a bookmark's number is minted by the resident aggregate.** Spec §3.1 places memory's events within `resident-<id>`; Commanded holds one aggregate per stream, and the resident aggregate is another system's. `mint_id` was built for this (agathos-daimon #4): the number is the resident's sequence, so `lily:bookmark/42` survives a rebuild and two residents never interleave, and the stream is memory's own. The records export reads the resident stream only, so bookmarks are not exported yet; the same open question as the ledger's (nisaba #9), now with the one store a resident would most want in its repository.
- **#20 The index is pins first and at most half the budget, then the rest by weight and recency, and it says how many it left out.** Built pure from the bookmark rows under `KUMBUKUMBU_INDEX_TOKENS` (1,500, the plan's guess), one line a bookmark: number, day, pin, tags, the resident's line. The footer names the ways past it (`bookmark_open`, `bookmark_list`, `transcript_search`) and, when the pins' half left a pin out, how many and that `bookmark_list(pinned: true)` lists every pin (#39). The injection carries the verbatim text, which is seen only in the turn's inspector (spec §5), and the numbers it listed, from which each row's `last_indexed_at` is derived. Every weight is 1.0 until weighting (F11) is measured, so the rest order by recency.
- **#21 A bookmark's words are the resident's; the tag set is the witness's; pins and taggings are either's.** Held at the command edge by the actor's kind: only the resident's actor adds, extends or declines; only the witness's creates, approves, rejects or retires a tag; a tag is a slug of at most 40 characters, a bookmark's line at most 120, and a tagging targets a bookmark by number, a conversation by key or a turn by ref, each checked to exist. The witness's proposal (`BookmarkProposed`, with a note) becomes a bookmark only when the resident writes one naming it, and the bookmark records who proposed.
- **#22 The span is turns, not instants, and the anchor may be the turn in flight.** `turns_back` counts captured turns back from the anchor, so a span never cuts a turn in half; the brain bookmarks mid-turn with the turn's ref and start instant, and the span resolves once the turn is captured at its end.
- **#24 Moved: behaviours are habits in the character layer.** Built here in P1 slice 4 as rows on the memory stream with enactments as taggings; moved in v0.2 to `Oneiroi.Ethos` (ethos #3 to #9), where a habit cites memory's moments and never lives among them. Memory keeps the moments (turns, bookmarks) and gives this system `turn_messages/2` and `bookmark/2` to read them; `habit` and `seed` are tagging target kinds here, checked for the kind alone (#27).
- **#25 Moved: the trigger lane is the character layer's.** `how_i_act/2` is `Oneiroi.Ethos.how_i_act/2` now (ethos #9), retrieval of its own that the index's scoring never pools with.
- **#26 An adapter's open turn is on the session row, and a wire instant is normalised before it is written.** `TurnStarted` sets `open_turn_ref` and the capture carrying that ref clears it, so the MCP server knows which turn a tool call belongs to (spec §8). An adapter once sent `sent_at` at second precision and the cast to `utc_datetime_usec` crashed the projector, which took the whole event-handling tree down with it; the projector now pads every instant to microseconds, and the adapter test captures at second precision as the guard.
- **#23 Compaction is a summary on the session with the store sequence it covers, and the live transcript is what follows.** `Compacted` is the conversation stream's; the session row holds the latest summary and watermark; the brain's live window reads messages after the watermark in one statement, joined on it, because the capture-cost test budgets that read. Nothing is deleted: the transcript, search and the spans read every message.
- **#31 The index names its near-misses.** `Index.build/2` returns, beside the lines it took, every bookmark it ranked and did not take in rank order with the reason it lost: a pin past the pins' half of the budget, or a line ranked at its weight below what the budget held. The brain records them as rows carrying no `refs` (brain #27), so the projector's `last_indexed_at`, derived from `refs`, never marks a near-miss as indexed.
- **#32 Tags are citations, and the tree's tags reach a moment through a port.** (Spec §6.17, P39.) A moment is tagged by the tree node it evidences, a soul line, a habit or a seed, and that tag is the node's citation of the moment in the character layer, never a row here: `bookmarks/1`, `bookmark/2` and so the index show each bookmark's closed-set tags and then the tree's (`soul/3`, `habit/2`, `seed/1`), read through `Oneiroi.Kumbukumbu.Tree`, the port named in `KUMBUKUMBU_TREE` (ethos, in every build so far) and called at the read, because the character layer reads this system's moments (ethos #3) and a call back is the cycle (sunna #12's shape). A pin is leaf-evidence of a soul line and which line it evidences is the pin's tag: `BookmarkPinned` is version 2 with `evidences`, the line's number or nil, checked here for shape alone (`kumbukumbu_evidence_invalid`) since the lines are the resident system's rows; a standing pin that now names a different line is recorded again, since its tag changed, and an unpin clears it. The line's own citation of the bookmark is written beside the pin by `Oneiroi.Ethos.pin_as_evidence/4`, one call from the pin's route. The closed set stays for work and project labels, and `tagged/2` reads it alone.
- **#33 A bookmark carries the register it was written in, tagged by the resident at write time and never judged after.** (Spec §6.13, P8.) `BookmarkAdded` is version 2 with `register`, one of `Oneiroi.Register`'s four (correction, praise, instruction, play) or nil, refused otherwise (`kumbukumbu_register_invalid`); the brain's `bookmark_add` takes it beside the line, and no model call or nightly pass assigns one, because the point is what the resident chose to write down and how it named it. The audits count the month's bookmarks and journal entries by it (huginn-muninn #18); the list in the kernel because two systems write it and a third counts across both.
- **#34 The madeleine is one adjacent, unheard bookmark a turn, gated and logged, never ranked.** (Spec §6.3, P10; Muninn: "the way a smell drags you into a room you haven't stood in for years".) `madeleine/3` refreshes `kumbukumbu_vector` (every bookmark's line and summary, and the limits, the contract's text, embedded through the provider port at `KUMBUKUMBU_EMBEDDING_MODEL` and `KUMBUKUMBU_EMBEDDING_WIDTH`, re-embedding only what changed; nothing at all for a resident with no bookmark), embeds the turn's words once, and takes the nearest bookmark within `KUMBUKUMBU_MADELEINE_DISTANCE_PERCENT` (80, a guess) that passes every gate: not pinned (the pins are in the index), not in the index for `KUMBUKUMBU_MADELEINE_UNHEARD_DAYS` (14, a guess: adjacent but unheard), not recalled for `KUMBUKUMBU_MADELEINE_REPEAT_DAYS` (30, a guess: non-repeating), and not within the same distance of the limits (P2: serendipity leaves the limit-adjacent alone); unstated limits are no words to be adjacent to, and the reason says so. The brain injects it as `madeleine` with its reason, a section of its own the index's scoring never sees (brain #30); the injection's refs mark `last_recalled_at`, the recall's own log. A regression trial reads it with `refresh: false` and `purpose: :regression` (`madeleine/5`): the vectors as they stand and the query billed with the trial, so the read writes nothing (brain #16). The rows are a cache of model output, the character layer's lane pattern (ethos #16), never events.
- **#35 An injection's refs mark bookmarks by the injection's label.** The `index` injection's refs set `last_indexed_at` and the `madeleine`'s set `last_recalled_at`; any other label's refs are not bookmarks. Until the madeleine landed every injection's refs were read as bookmark numbers, so the character section's habit numbers marked bookmarks of the same number as indexed: habit #1 marked bookmark #1 heard every turn it matched. Found by the madeleine's unheard gate, which read a bookmark as heard that the index had never listed.
- **#36 A session names its room, and retrieval respects it: the index, the search, the madeleine and the lane's exemplars reach the room's sessions and the common room's, never another domain's.** (Spec §6.3, P23; Red: "I don't want certain domains of my life crossing into one another.") `SessionOpened` is version 2 with `domain`, a slug the witness names at the opening (`open_session/6` with `domain:`, `POST /residents/:id/sessions` with `domain`) or nil for the common room; the aggregate refuses another shape (`kumbukumbu_domain_invalid`); the main session is the common room. `room/2` is the rule in one place: a session's domain and the keys of every session retrieval may reach from it, the sessions of the same domain and the common room's, so the common room sees the common room alone and a domain's material never reaches a session that did not name it; a key no session has is the common room. `index/2` builds over the room's bookmarks and names a bookmark of another domain that would have ranked in among the near-misses as held behind the domain line, so the audit shows the line approached and not crossed (brain #27 records it as a row); `search/5` and `madeleine/4` take the room; the lane's exemplars take it through the situation's `session_key` (ethos #19). Shipped as an intent with an audit, as Red asked, not a proof: a transcript read by number, `bookmark_open` and the unscoped `index/1` are not room-scoped, and the pass that would be is the brain's; `bookmark_list` pages within the room (#39).
- **#37 A session carried from another platform is of kind `imported`, opened only by the import and read by no nightly pass.** `open_imported/4` opens one in the common room with the source platform as its adapter and the witness as its party, so the witness reads it as any solo transcript; its turns are captured with `capture/6` and their original instants. The aggregate accepts the kind; `open_session/6` refuses it (`kumbukumbu_kind_invalid`), so no client opens one. `messages_between/3`, the nightly pass's read (eunomia #4), leaves imported sessions out: their messages carry their original days, which the other platform judged already. Search, the index and bookmarks reach them as any session's.
- **#38 The Memory screen's index is the build as it stands, read from the server, never inferred from a turn's marks.** `index_now/1` (`GET /residents/:id/index`, the witness's, as every memory route is) is `index/2` over the common room, the room the main session is: the numbers listed in the index's order, the room's left-out count, how many bookmarks sit in a named room and are listed only in its sessions, the budget, and a sentence that says all of it. The client renders the numbers and the sentence and holds none of the rule: no budget, no pin share, no ordering, no filter on `last_indexed_at`, which stays a fact on the row (when a turn last listed it) and never the tab's filter. The common room rather than the unscoped `index/1` because the Memory tab sits beside the main conversation and a list that named a named room's bookmarks would show the witness an index no turn of theirs is given.
- **#39 The brain pages back past the index through `bookmark_list`, within its room.** `bookmark_page/3` lists the bookmarks of the room of the turn's session (`room/2`, as `index/2` reads it, so a bookmark held behind the domain line is never listed to another room's session) newest first, at most `KUMBUKUMBU_PAGE_BOOKMARKS` (20, a guess) a page, narrowed by `before` (a number to page back from), `pinned` (the pins alone, every one, the ones the index's half could not fit included), `tag`, `text` (a phrase in the line, any case) and `from`/`to` (the anchor's day), each combined with the rest, and says how many more match further back. The brain's tool renders each row as `Index.line/1` does and closes with the next page's `before`, or that nothing further back matches: the index footer's honesty, carried to the page.
- **#30 A revision adds beside a memory and never overwrites it, and a stance is the resident's to agree.** `revise/3` writes `RevisionApplied{number, target_kind, target_id, kind, text}` with the reason as its note for a fact by either party or a stance by the resident, and `RevisionProposed` for a stance the witness corrects, which the resident accepts (`RevisionApplied` with the acceptance as the decision note) or declines, each with a note shown to both (F13). Numbers count per resident on the memory stream; a target is any tagging kind, a bookmark checked to exist; the target's own words stand, and the revisions are read beside them (`revisions_of/3`, the brain's `bookmark_open`). The witness never rewrites the resident's words in a bookmark (#21): a revision is the only correction there is.
- **#28 A private session is a locked row to its account party until the resident shares it.** `open_session/6` with `private: true` writes `SessionMadePrivate` beside `SessionOpened`; the projector keys the session's messages to the resident instead of the account party, so the account scope's policy answers none of them, and `transcript/2` under an account scope refuses a private, unshared session with `kumbukumbu_session_private`: the row lists (kind, parties, no open) and nothing opens. `SessionShared` keys the messages back to the party. The schedule opens free time this way under the contract's privacy term (sunna #19, agathos-daimon #22); the resident always reads its own.
- **#29 A revealed wall re-keys the earlier sessions to the new witness.** The projector folds the resident system's `EarlierSessionsRevealed{from, to}` (agathos-daimon #24): every account-keyed row of the resident (sessions, messages, capture failures, injections) not keyed to the resident itself becomes the new witness's, whoever witnessed before. The first version moved the handing witness's rows alone, so a session from two witnesses back stayed where it was; the custody suite found it.
- **#27 A tagging on another system's row is checked for its kind alone, and the day's messages are a read.** `position`, `prediction`, `date`, `figure`, `document` and `journal` join the target kinds (spec §6.3's list) with no existence check here, as a `turn` has none: the row is its system's and a tagging that names a number that never was is that system's to report. `messages_between/3` reads every message sent in an interval across the resident's sessions, for the nightly pass (eunomia #18).

## #8 Initial vs target

Initial (P1, slice 2): #1, with the brain's turns and an adapter's
captures landing in it. Target: the whole of spec §6.3: bookmarks with
spans and pins, the closed tag set and taggings across kinds, the index
under its budget with the left-out count, weighting, revision,
compaction, and the conversation streams in the records export. The
behaviours (#10 to #13 of the function doc) were built here in P1 and
moved to the character layer in v0.2 (ethos).

## #9 Depends on

The platform and whatever spec §14's row for its phase names.

## #13 Ethos, behaviours

Greek, EE-thos.

> "moral virtue comes about as a result of habit, whence also its name (ethike) is one that is formed by a slight variation from the word ethos (habit)." — Aristotle, Nicomachean Ethics II.1, 1103a, trans. W. D. Ross (Oxford, 1925)

Ethos is character, and Aristotle hears habit inside it: the two words differ by one vowel, and he takes that as the lesson. Character is not stated; it is what repeated action leaves behind.

The behaviours part was built here in P1 slice 4 (`Oneiroi.Kumbukumbu.Ethos`) and the name went with it when it became a system of its own in v0.2: the character layer, `systems/ethos.md`, where the story now lives. What stayed here is the moments a habit cites.

