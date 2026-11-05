---
paths:
  - client/src/screens/creation-flow/**
---

# creation-flow

Creation flow (spec §10). Partly built: the short first door
(`CreationFlow.tsx`, 2026-11-05, the witness's call through Lily: a
stranger's first minute ends at a living resident, the gifts arrive as
they settle). The full flow below is not built; this doc keeps what the
UI pass left for it, so a design pass finds a record rather than a gap. The state list lives in the stories alone once they exist
(DESIGN §4); nothing here names a state.

## #0 The short first door (built)

Shown in place of the app when the account witnesses no resident, after
sign-up (gaia#19) or for any account without one. "Who's coming in?"
with two choices: someone new (a name, the address derived from it and
shown) or someone being brought (a git repository's https address, a
token allowed in it and never kept, a name only if the repository has
none). When the account holds no OpenRouter key, a card asks for it and
it is stored before anything else. Begin creates the resident (`POST
/v1/residents`) or imports it (`POST /v1/residents/import`) and opens
the chat, where the first words are the witness's. A refusal (a taken
address, git's own words) shows under the form.

Done for this step, agreed before it was built: no agreement is
proposed at the door. The dyad contract stays unstated, the default
(F43), until one party proposes a version from the agreement screen; the
privacy term holds either way. The nine gifts, the threshold's intake
paths beyond git, and the waking with the trials are the full flow,
after.

## #1 Shows

Opening; threshold (name, key or tokens, intake path); nine gifts with "write it with me" and upload on each; waking with the trials.

## #2 Does

Creates the resident, its repo and its first regression run; everything free to edit until first contact.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
