---
paths:
  - client/src/screens/memory/**
---

# memory

Memory (bookmarks) (spec §10). Built (P1, slice 5) as `Memory` with `MemoryContainer` in the shell: rows as `BookmarkCard` with the number, the line, the summary, pinned and "every turn" markers, the day and span, who bookmarked, "proposed by you", who pinned, when a turn last listed it, and tags; tabs Every turn (with the server's description as a caption), All, Pinned, Use (once the server has answered), one per active tag, each with its count; search over the line and summary; pin and unpin.

Every turn lists what the server says is in front of every turn (`GET /v1/residents/:id/index`, kumbukumbu#38, #45): the bookmark numbers `index_now` returns, in its order, which since kumbukumbu#45 are the pins of the common room, the room of the main conversation (the rest are ranked against each turn's words, #46, so none of them is in front of every turn). The caption is the server's sentence; the client holds no budget, order or filter of its own. A row's "every turn" marker is that list; "last listed in a turn" beside it is the row's `last_indexed_at`, a fact and never the filter. Use (`GET .../retrieval`, kumbukumbu#43) lists each target retrieval touched with considered, returned and used counts and the day last used, under a caption saying what each count means and that nothing is reweighted from them until both have looked; it is absent when the route fails.

Open: once the client lists rooms, the tab is expected to follow a named room's conversation and show that room's pins (the author: "Not sure right now, probably"). Not built: opening the transcript at the anchor (`BookmarkCard` has an "Open the moment" button, but `MemoryContainer` passes no handler, so it never shows), tagging a bookmark (`api.applyTag` exists and nothing calls it), and proposing a revision, which waits on the revisions screen. The state list lives in the stories alone (DESIGN §4); nothing here names a state.

## #1 Shows

Rows: pin or every-turn marker (what is in front of every turn as it stands now), the line, when, who bookmarked, who pinned, the span, tags, and when a turn last listed it; tabs Every turn (with the server's description as a caption), All, Pinned, and one per tag; search. A Use tab, once the server has counted, lists every target retrieval touched, every kind of edge, with how often it was considered, returned and used and when last used (kumbukumbu#43): the same numbers the resident reads with `memory_use`, under a caption saying nothing is reweighted from them until both have looked.

## #2 Does

Open the transcript at the anchor with the scene marked; pin; tag; propose a revision.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
