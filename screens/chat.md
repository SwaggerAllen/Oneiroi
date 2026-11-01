---
paths:
  - client/src/screens/chat/**
---

# chat

Chat (home) (spec §10). Built (P1, slice 5) as `Chat` with `ChatContainer` in the shell: the transcript with refusals in the resident's words, the streamed reply over the session channel, "drew on N things" over the turn's injections, a bookmark proposal from a reply, and "What Lily will see next", the preview of the next turn (brain #41).

The preview sits beside the inspector: the inspector is what a turn drew on, the preview what the next would, from `POST /v1/residents/:id/sessions/:key/preview` with the draft as it stands. The server sends every section in its order with label, tokens, reason, its words where you already read them elsewhere and otherwise a line saying why not, and a description of the whole; the client renders them and decides nothing (which sections exist, their order, their counts, what is withheld). Opening it records nothing and bills nothing; sending closes it. Long words wrap on a phone. The check-engine light, reports and the session line wait on their systems. The state list lives in the stories alone (DESIGN §4); nothing here names a state.

## #1 Shows

The main conversation as a transcript; the check-engine light and the session line (last and next check-in) in the top bar; refusals in the resident's words; a "drew on N things" inspector per reply; the preview of what the next turn would be given; reports filed by either party and each investigation step inline.

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
