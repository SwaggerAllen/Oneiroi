---
paths:
  - lib/oneiroi/kumbukumbu/**
  - lib/oneiroi/kumbukumbu.ex
  - lib/oneiroi_web/controllers/conversation_controller.ex
  - priv/repo/migrations/*_kumbukumbu.exs
  - test/oneiroi/kumbukumbu/**
---

# kumbukumbu

**Memory.** Swahili, koom-boo-KOOM-boo.

> "1 remembrance, memory, mind, anniversary; souvenir. 2 records, minutes (of a meeting/conference): ~ za kihistoria annals" — TUKI Swahili–English Dictionary (Univ. of Dar es Salaam), entry kumbukumbu

In Swahili, *kumbukumbu* names the act of keeping: remembrance, commemoration, the anniversary — and "minutes," the written record of what a meeting said.

The memory subsystem is named for what it does rather than what it stores: it remembers, commemorates, and keeps the minutes. Remembering is something you do for someone; storage is something you do to something. That difference is the design.

Transcripts, bookmarks, tags, search, weighting, the memory agent's
record. Spec §6.3. Transcripts are built (P1, slice 2); the rest is this
doc's file map and the standing decisions the spec records, so a pass
reaching for it finds a record rather than a gap.

## #1 Owns

The conversation aggregate on `conversation-<resident_id>-<session_key>`
and its v1 events (`SessionOpened`, `TurnStarted`, `TurnCaptured`,
`ContextAssembled`, `CaptureFailed`, `CaptureFailureResolved`,
`SessionShared`); the `kumbukumbu_session`, `kumbukumbu_message`,
`kumbukumbu_capture_failure` and `kumbukumbu_context_injection`
projections, scoped by the resident and by the account party to the
session; the session, transcript, search, capture-failure, injection and
adapter capture routes under `/v1/residents/:id`.

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

The behaviours part (spec §6.3, F55; #10 and #11 above): how a resident tends to act, kept as rows with their triggers and the turns that enacted them, is named for the word that already says the design. A behaviour is a habit that has become character, and what carries over to a new model is the habit, not the description of it.

