---
paths:
  - lib/oneiroi/brain/**
  - lib/oneiroi/brain.ex
  - lib/oneiroi_web/channels/**
  - priv/prompts/brain.md
  - priv/prompts/budget_stop.md
  - test/oneiroi/brain/**
  - test/oneiroi_web/channels/**
---

# brain

The resident's canonical agent loop (spec §5). Named for its function
until the author names it, as the client is (`design/names.md`): the
spec's §6 does not list it among the systems, and §8 ships it as the
`brain` adapter, the core's own.

## #1 Owns

The session process (`Oneiroi.Brain.Session`, one per active session,
started on the first turn, holding nothing the event store does not),
the turn (`Oneiroi.Brain.Turn`), the brain's prompt file and the budget
stop notice, the socket and the session channel.

## #2 Standing decisions

- **#3 A turn is assemble, call, stream, capture (spec §5).** The
  context is the prompt file with the resident's name and the session's
  last messages (`BRAIN_TRANSCRIPT_MESSAGES`, a bound), each recorded as
  an injection with its reason and a token count estimated at four bytes
  a token; the identity files, the bookmark index and the behaviours join
  it as the slices that build them land, as more recorded injections.
- **#4 Three endings, all honest.** A reply, refusal included, is an
  ordinary `TurnCaptured` with the refusal flagged on the message. A
  budget stop captures the steward's message and a notice from
  `priv/prompts/budget_stop.md` as a system message by the platform, so
  both parties read it in the same place (spec §5, §6.11). A provider
  failure captures nothing and records a capture failure the steward can
  mark lost.
- **#5 One process per session, and turns on it run one at a time.** Two
  messages sent at once capture as two turns in order rather than
  interleaving; the process is a `GenServer` under a `DynamicSupervisor`
  found through a `Registry`, both declared in `processes/0`.
- **#6 The socket's principal is a token, never the cookie.** Phoenix's
  session on a socket wants a CSRF token this app does not keep (its
  CSRF defence is the Origin check, `systems/gaia.md` #5); the client
  mints a five-minute socket token at `POST /v1/me/socket-token`, a
  script uses its API token, and `check_origin` against the endpoint's
  own host is the socket's equivalent of the Origin check.
- **#7 The chat model is a setting until the pin lands.**
  `BRAIN_CHAT_MODEL` is a placeholder the steward's pin
  (`ModelPinChanged`, spec §6.4) replaces; its default was chosen for
  being cheap and widely served, not measured.

## #8 Initial vs target

Initial (P1, slice 2): #1, over the main session. Target: free-time
sessions on their own budget line, sessions opened by wake, tools from
the MCP tool table by role, compaction with the memory flush, the
identity files and the index in the context (spec §5).

## #9 Depends on

The ledger for every model call; memory for capture, the transcript and
the context record; the resident system for the resident's name and,
later, its files and pin.
