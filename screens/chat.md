---
paths:
  - client/src/screens/chat/**
---

# chat

Chat (home) (spec §10). Not built: this doc is the screen's file map and
what the UI pass left for it, so a design pass finds a record rather
than a gap. The state list lives in the stories alone once they exist
(DESIGN §4); nothing here names a state.

## #1 Shows

The main conversation as a transcript; the check-engine light and the session line (last and next check-in) in the top bar; refusals in the resident's words; a "drew on N things" inspector per reply; reports filed by either party and each investigation step inline.

## #2 Does

Send; open a cited target in the panel; pin or propose a bookmark from a reply; search transcripts, open a new session, file a report from the menu.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
