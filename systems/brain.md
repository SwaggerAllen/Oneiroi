---
paths:
  - lib/oneiroi/brain/**
  - lib/oneiroi/brain.ex
  - lib/oneiroi_web/channels/**
  - priv/prompts/brain.md
  - priv/prompts/budget_stop.md
  - priv/prompts/memory_flush.md
  - priv/prompts/compaction.md
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
the turn (`Oneiroi.Brain.Turn`), the tool set (`Oneiroi.Brain.Tools`),
compaction (`Oneiroi.Brain.Compaction`), the brain's prompt file, the
budget stop notice, the memory flush and compaction prompts, the socket
and the session channel.

## #2 Standing decisions

- **#3 A turn is compact if due, assemble, call, run the tools, stream, capture (spec §5).** The
  context is the prompt file with the resident's name, the bookmark
  index under its budget (kumbukumbu #20), the compaction summary when
  there is one, and the session's last messages since its compaction
  (`BRAIN_TRANSCRIPT_MESSAGES`, a bound), each recorded as an injection
  with its reason and a token count estimated at four bytes a token; the
  identity files and the behaviours join it as the slices that build
  them land, as more recorded injections.
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
- **#10 The tools are the resident's memory functions and never a steward operation.** `Oneiroi.Brain.Tools` offers `bookmark_add`, `bookmark_extend`, `bookmark_open`, `bookmark_accept`, `bookmark_decline`, `tag_list`, `tag_propose`, `tag_apply` and `transcript_search` (spec §8's memory table, the part built so far), run against the core's exports under the resident's actor, so the role checks of kumbukumbu #21 hold for a tool call as for a route. A round is one streamed call; tool calls go back as `tool` messages for the next round, up to `BRAIN_TOOL_ROUNDS` (a bound), after which the model's last words stand. Every call the model made is captured in the turn as a `tool` message naming the call and its answer, so the transcript is full (spec §6.3). A tool the model misuses answers in words rather than failing the turn.
- **#11 Compaction opens the turn that finds the session over the line, with a memory flush first.** When the messages since the last compaction reach `BRAIN_COMPACT_AFTER_MESSAGES` (80, twice the live window, a guess), the turn opens by giving the resident those messages and its tools under `memory_flush.md`, then asks for a summary under `compaction.md` folding in the previous one, and records `Compacted` with the watermark (kumbukumbu #23). Both calls are chat on the ledger. If either fails the turn goes on uncompacted and the next one tries again. Compaction never deletes a message.

## #8 Initial vs target

Initial (P1, slices 2 and 3): #1, over the main session, with the memory
tools, the index and compaction. Target: free-time sessions on their own
budget line, sessions opened by wake, the rest of the MCP tool table by
role, the identity files and the behaviours in the context (spec §5).

## #9 Depends on

The ledger for every model call; memory for capture, the transcript and
the context record; the resident system for the resident's name and,
later, its files and pin.
