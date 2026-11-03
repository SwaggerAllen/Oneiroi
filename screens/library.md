---
paths:
  - client/src/screens/library/**
---

# library

Library (spec §10), partly built 2026-11-02: `client/src/screens/library/`
(`Library.tsx`, `paths.ts`, stories and tests), under More, loaded by
`LibraryContainer` in `client/src/app/App.tsx` from
`GET /v1/residents/:id/library` and `.../library/documents/*path`. The
state list lives in the stories (DESIGN §4).

Built: a tab per kind across the top, All first and each with its
count, in the order keepsakes, yours (`human/`, always present so the
first can be added), the resident's kinds, scratch and the journal last
(the tabs wrap on a phone rather than scroll, so none is out of sight).
A Find box narrows the tab by title and path as you type; "Search the
words" runs the library's own index (`GET .../library/search?q=`, one
embedding call, so it is a button rather than per keystroke) and shows
the passages found for the tab, each opening its document. Keepsakes
carry why each mattered in the resident's words (seshat #32); a document
opens and reads whole; scratch and human documents are removed with the
button turned into its consequence; a document of yours is added, on the
Yours tab, by pasting or from a .md or .txt file, under a name made safe
(`humanPath`). Not built:
writing by status with the review copy, publish, research tasks and
source release, digests, the journal's plan versus actuals, feeds,
adopting a file made outside the flow.

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
