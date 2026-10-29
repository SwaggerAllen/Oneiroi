---
paths:
  - client/src/screens/ledger/**
---

# ledger

Ledger (spec §10). Built (P1, slice 5) as `Ledger` with `LedgerContainer` in the shell: key status with store or rotate, budget lines with spend and the stop, spend by purpose, model and actor, and setting a line. Platform tokens wait on their phase. The state list lives in the stories alone (DESIGN §4); nothing here names a state.

## #1 Shows

Key status; budget lines with spend; spend by purpose and by model and actor; platform token balance and markup.

## #2 Does

Set a budget line; rotate the key; buy tokens.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
