---
paths:
  - client/src/screens/memory/**
---

# memory

Memory (bookmarks) (spec §10). Built (P1, slice 5) as `Memory` with `MemoryContainer` in the shell: rows as `BookmarkCard` with pin, index marker, the line, when, who bookmarked, who pinned, the span and tags; tabs In the index (with the server's description as a caption), All, Pinned, one per active tag; search over the line and summary; pin and unpin.

In the index lists what the index holds now (`GET /v1/residents/:id/index`, kumbukumbu #38): the bookmark numbers the server's build listed, in its order, for the common room, which is the room of the main conversation, so a bookmark made in a named room is counted there and listed only in that room's conversations. The caption is the server's sentence, budget and all; the client holds no budget, pin share, order or filter of its own. A row's "in the index" marker is that list; "last listed in a turn" beside it is the row's `last_indexed_at`, a fact and never the filter, so the tab is right before any turn has been taken.

Open: once the client lists rooms, the tab is expected to follow a named room's conversation and show that room's index (the author: "Not sure right now, probably"). Opening the transcript at the anchor and proposing a revision wait on the transcripts and revisions screens. The state list lives in the stories alone (DESIGN §4); nothing here names a state.

## #1 Shows

Rows: pin or index marker (the index as it stands now), the line, when, who bookmarked, who pinned, the span, tags, and when a turn last listed it; tabs In the index (with the server's description, budget included, as a caption), All, Pinned, and one per tag; search.

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
