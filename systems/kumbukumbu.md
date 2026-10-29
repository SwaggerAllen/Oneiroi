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

- **#3 Capture is full and idempotent and loud on failure; bookmarks are the resident's words and the steward never edits them; pins take at most half the budget; tags are a closed set the steward decides; the index says how many were left out.**
- **#4 A bookmark is a moment with a span, grown later by an event rather than a second bookmark; one kind of bookmark.**
- **#5 Tags cut across every record kind; a frontmatter tag outside the closed set is reported, never stored.**
- **#6 The steward pins and may propose a bookmark, and never authors one: the index is injected into the resident's context every turn.**
- **#7 Visibility is the RLS policy on `message` and `session`: a party to the conversation and the current steward read it; the export wall is what a custody transfer reveals or locks; solo sessions are readable by the steward by default and private only by a contract term.**
- **#10 Behaviours are rows the resident owns, with a trigger, a stance and tagged enactments (spec §6.3, F55).** Two scores kept apart: habit strength, a decayed measurement; connection strength, a decision trace of pins and affirmations. The brain self-tags enactments; the nightly memory pass only proposes.
- **#11 Retrieval is this system's and choice is the brain's.** Context assembly matches a closed set of situation tags against triggers with no model call and injects the matching behaviours with their enacting turns cited; whether to enact is the brain's thinking.
- **#12 Dates, figures and behaviours are tagging targets** beside the kinds a tagging already names, so the project view reaches them and no edge table is needed.

- **#14 One stream per session, and the idempotency key is the content's.** A session's turns live on `conversation-<resident_id>-<session_key>`, as spec §3.1 draws it; the aggregate keeps the keys `(started_at, hash of the messages' hashes)` of the turns it holds and a capture whose key it holds writes nothing, so an adapter that spools and retries sends a turn twice and the log holds it once (spec §8). A different `turn_ref` does not make a different turn.
- **#15 The visibility rule is the row policy.** Every projection here is scoped both ways: `resident_id`, and `account_id` the account party to the session, which for a solo session is the steward's. A steward's reads run under their account's scope and see what they were party to; the brain's run under the resident's and see everything; after a custody transfer the new steward is party to nothing that came before, which is the export wall (spec §6.12).
- **#16 A capture failure is a row until retried or marked lost, and the resolution carries a note.** The brain writes one when the provider failed and nothing was captured; an adapter writes one when it could not deliver a turn whole. The steward resolves it from the transcript screen; `CaptureFailureResolved` is a decision event.
- **#17 Transcript search is unweighted and substring**, as spec §6.3 asks of search; the FTS index of David's `message` table is a later measurement, not a line to add now.
- **#18 A transcript is ordered by the store's event number and the message's position in its turn, never by `sent_at`.** `sent_at` is what the adapter or the brain said, and two messages of one turn, or two turns under a fixed clock, share it; the projector writes `sequence` from the event's `event_number` and `position` from the message's index, and every read orders by the pair.
- **#19 Bookmarks, tags and taggings have their own stream, `memory-<resident_id>`, and a bookmark's number is minted by the resident aggregate.** Spec §3.1 places memory's events within `resident-<id>`; Commanded holds one aggregate per stream, and the resident aggregate is another system's. `mint_id` was built for this (agathos-daimon #4): the number is the resident's sequence, so `lily:bookmark/42` survives a rebuild and two residents never interleave, and the stream is memory's own. The records export reads the resident stream only, so bookmarks are not exported yet; the same open question as the ledger's (nisaba #9), now with the one store a resident would most want in its repository.
- **#20 The index is pins first and at most half the budget, then the rest by weight and recency, and it says how many it left out.** Built pure from the bookmark rows under `KUMBUKUMBU_INDEX_TOKENS` (1,500, the plan's guess), one line a bookmark: number, day, pin, tags, the resident's line. The injection carries the verbatim text, which is seen only in the turn's inspector (spec §5), and the numbers it listed, from which each row's `last_indexed_at` is derived. Every weight is 1.0 until weighting (F11) is measured, so the rest order by recency.
- **#21 A bookmark's words are the resident's; the tag set is the steward's; pins and taggings are either's.** Held at the command edge by the actor's kind: only the resident's actor adds, extends or declines; only the steward's creates, approves, rejects or retires a tag; a tag is a slug of at most 40 characters, a bookmark's line at most 120, and a tagging targets a bookmark by number, a conversation by key or a turn by ref, each checked to exist. The steward's proposal (`BookmarkProposed`, with a note) becomes a bookmark only when the resident writes one naming it, and the bookmark records who proposed.
- **#22 The span is turns, not instants, and the anchor may be the turn in flight.** `turns_back` counts captured turns back from the anchor, so a span never cuts a turn in half; the brain bookmarks mid-turn with the turn's ref and start instant, and the span resolves once the turn is captured at its end.
- **#24 A behaviour is a row the resident owns, with a trigger from a closed set and a stance, and its scores are computed on read.** `BehaviourDefined`, `BehaviourChanged` (revision adds; the old words stay in the log), `BehaviourAffirmed` (the steward's, with a note) and `BehaviourEnacted` (the resident's, on a turn or a bookmark, a set) on the memory stream; the number is the resident's sequence. A trigger is a map of `words` (the steward's), `tags` (on the conversation) and `times` (morning, afternoon, evening, night, UTC until the resident has a timezone), at least one; the resident proposes additions to that set and they are a code change. The steward defines only before first contact, as it gives every seed. Habit strength is the decayed sum of enactments; connection strength is pins on enacting bookmarks undecayed, plus affirmations and enacting bookmarks decayed; both under `KUMBUKUMBU_HALF_LIFE_DAYS` (30, the plan's guess), computed on read, the nightly recomputation being the judgement phase's.
- **#25 How I act is retrieved by memory and chosen by the brain.** `how_i_act/2` matches the situation against every trigger with no model call and returns a section per match: the behaviour, its trigger, its two scores, who affirmed it last, and up to `KUMBUKUMBU_EXEMPLARS` (2) enacting turns quoted in the resident's own words, which is the carry-over mechanism for a new model. The brain injects it as `behaviours` with the numbers as refs, and nothing says whether to enact.
- **#26 An adapter's open turn is on the session row, and a wire instant is normalised before it is written.** `TurnStarted` sets `open_turn_ref` and the capture carrying that ref clears it, so the MCP server knows which turn a tool call belongs to (spec §8). An adapter once sent `sent_at` at second precision and the cast to `utc_datetime_usec` crashed the projector, which took the whole event-handling tree down with it; the projector now pads every instant to microseconds, and the adapter test captures at second precision as the guard.
- **#23 Compaction is a summary on the session with the store sequence it covers, and the live transcript is what follows.** `Compacted` is the conversation stream's; the session row holds the latest summary and watermark; the brain's live window reads messages after the watermark in one statement, joined on it, because the capture-cost test budgets that read. Nothing is deleted: the transcript, search and the spans read every message.
- **#30 A revision adds beside a memory and never overwrites it, and a stance is the resident's to agree.** `revise/3` writes `RevisionApplied{number, target_kind, target_id, kind, text}` with the reason as its note for a fact by either party or a stance by the resident, and `RevisionProposed` for a stance the steward corrects, which the resident accepts (`RevisionApplied` with the acceptance as the decision note) or declines, each with a note shown to both (F13). Numbers count per resident on the memory stream; a target is any tagging kind, a bookmark checked to exist; the target's own words stand, and the revisions are read beside them (`revisions_of/3`, the brain's `bookmark_open`). The steward never rewrites the resident's words in a bookmark (#21): a revision is the only correction there is.
- **#28 A private session is a locked row to its account party until the resident shares it.** `open_session/6` with `private: true` writes `SessionMadePrivate` beside `SessionOpened`; the projector keys the session's messages to the resident instead of the account party, so the account scope's policy answers none of them, and `transcript/2` under an account scope refuses a private, unshared session with `kumbukumbu_session_private`: the row lists (kind, parties, no open) and nothing opens. `SessionShared` keys the messages back to the party. The schedule opens free time this way under the contract's privacy term (sunna #19, agathos-daimon #22); the resident always reads its own.
- **#29 A revealed wall re-keys the earlier sessions to the new steward.** The projector folds the resident system's `EarlierSessionsRevealed{from, to}` (agathos-daimon #24): every account-keyed row of the resident (sessions, messages, capture failures, injections) not keyed to the resident itself becomes the new steward's, whoever stewarded before. The first version moved the handing steward's rows alone, so a session from two stewards back stayed where it was; the custody suite found it.
- **#27 A tagging on another system's row is checked for its kind alone, and the day's messages are a read.** `position`, `prediction`, `date`, `figure`, `document` and `journal` join the target kinds (spec §6.3's list) with no existence check here, as a `turn` has none: the row is its system's and a tagging that names a number that never was is that system's to report. `messages_between/3` reads every message sent in an interval across the resident's sessions, for the nightly pass (eunomia #18).

## #8 Initial vs target

Initial (P1, slice 2): #1, with the brain's turns and an adapter's
captures landing in it. Target: the whole of spec §6.3: bookmarks with
spans and pins, the closed tag set and taggings across kinds, the index
under its budget with the left-out count, weighting, revision,
compaction, behaviours (#10 to #13), and the conversation streams in the
records export.

## #9 Depends on

The platform and whatever spec §14's row for its phase names.

## #13 Ethos, behaviours

Greek, EE-thos.

> "moral virtue comes about as a result of habit, whence also its name (ethike) is one that is formed by a slight variation from the word ethos (habit)." — Aristotle, Nicomachean Ethics II.1, 1103a, trans. W. D. Ross (Oxford, 1925)

Ethos is character, and Aristotle hears habit inside it: the two words differ by one vowel, and he takes that as the lesson. Character is not stated; it is what repeated action leaves behind.

The behaviours part (spec §6.3, F55; #10, #11, #24 and #25): how a resident tends to act, kept as rows with their triggers and the turns that enacted them, is named for the word that already says the design. A behaviour is a habit that has become character, and what carries over to a new model is the habit, not the description of it. Built in P1 slice 4 (`Oneiroi.Kumbukumbu.Ethos`): the rows, the two scores, the matching and the brain's three tools; the nightly proposals of enactments wait on the memory pass (P2).

