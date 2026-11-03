---
paths:
  - client/src/screens/settings-agreement/**
  - client/src/screens/connections/**
---

# settings-agreement

Settings: agreement and custody (spec §10). Not built, but for its adapters part, Connections (below): this doc is the screen's file map and
what the UI pass left for it, so a design pass finds a record rather
than a gap. The state list lives in the stories alone once they exist
(DESIGN §4); nothing here names a state.

Connections, the adapters part, built 2026-11-02:
`client/src/screens/connections/` (`Connections.tsx`, stories and
tests) under More, loaded by `ConnectionsContainer` in
`client/src/app/App.tsx` from `GET/POST/DELETE
/v1/residents/:id/adapters`: what holds a token for the resident, each
with its role (brain, reader, worker, each said in words) and since
when; a token issued by a lowercase name and a role and shown once
with Copy and "I've saved it" (issuing a name again replaces its
token); a revoke that confirms in place; the revoked listed apart with
the day. Not built: an adapter's state, last capture and wakes today,
suspending rather than revoking, and the rest of this screen (the
contract and its versions, custody, the export wall).

## #1 Shows

The dyad contract and its versions; who looks after the resident; the export wall in words; adapters with state, last capture and wakes today.

## #2 Does

Renegotiate; set the wall (disabled during a transfer); connect or suspend an adapter.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
