---
paths:
  - client/src/screens/ledger/**
---

# ledger

Ledger (spec §10). Built (P1, slice 5) as `Ledger` with `LedgerContainer` in the shell, under More, from `GET /v1/residents/:id/ledger`: the OpenRouter key's status (stored since a day, or none) with store or rotate (`PUT /v1/me/key`, a password field); budget lines, each its spend of its cap a day, week or month, "no limit" when it has none and "stopped" when exceeded; setting a line (`PUT .../ledger/budgets/:purpose`) by purpose, a cap in dollars (blank for no limit) and a period; and spend since the start of the month by purpose, by model and by actor, each with calls and cost. The purposes are the server's list in its order (`Nisaba.Purpose`: chat, free_time, judge, hands, embeddings, oracle, drafting, regression), so a purpose the server adds, such as `oracle` (brain#49), is offered with no change here. Not built: platform token balance and markup, buying tokens. The state list lives in the stories alone (DESIGN §4); nothing here names a state.

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
