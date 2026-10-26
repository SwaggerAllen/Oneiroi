---
paths:
  - client/src/screens/library/**
---

# library

Library (spec §10). Not built: this doc is the screen's file map and
what the UI pass left for it, so a design pass finds a record rather
than a gap. The state list lives in the stories alone once they exist
(DESIGN §4); nothing here names a state.

## #1 Shows

Writing by status with the review copy, references resolved, conversations, copy for publishing; research tasks with their sources and release state; digests; the journal with plan versus actuals; feeds with errors; design and other kinds; files made outside the flow.

## #2 Does

Copy; publish; release or withhold a source, a task's sources or a pass; add or remove a feed, approve or decline a proposal; adopt a file.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
