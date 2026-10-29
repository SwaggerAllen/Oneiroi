---
paths:
  - client/src/screens/memory/**
---

# memory

Memory (bookmarks) (spec §10). Built (P1, slice 5) as `Memory` with `MemoryContainer` in the shell: rows as `BookmarkCard` with pin, index marker, the line, when, who bookmarked, who pinned, the span and tags; tabs In the index (with the budget as a caption), All, Pinned, one per active tag; search over the line and summary; pin and unpin. Opening the transcript at the anchor and proposing a revision wait on the transcripts and revisions screens. The state list lives in the stories alone (DESIGN §4); nothing here names a state.

## #1 Shows

Rows: pin or index marker, the line, when, who bookmarked, who pinned, the span, tags; tabs In the index (with the budget as a caption), All, Pinned, and one per tag; search.

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
