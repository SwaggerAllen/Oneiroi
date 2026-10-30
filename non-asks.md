# Oneiroi — confirmed non-asks

The negative space, recorded with reasons (orchestration's DESIGN §4).
Proposing one of these is not forbidden; do it knowing you are arguing
against a recorded decision, and say so.

**Schema** (orchestration's `nonasks` parser). One entry per `## `
heading; `scope:` is the line immediately under it, with no blank line
between, or the entry silently goes universal. Scopes are the mutex
labels, comma-separated, or `universal`. Everything above the first
heading is preamble and is never inlined into a prompt. Name every
system a refusal touches rather than the closest one.

**What belongs here.** A refusal about exactly one system is a standing
decision of that system and lives in its `systems/*.md`, beside the rule
it is the negative half of. This file holds the two kinds with no such
home: refusals every pass must see, and refusals that span systems.
Entries are never deleted by a pass; relocating one is an author move.
A refusal earns an entry only as the negative half of a rule stated
somewhere positive, never as a record that a pass considered an
approach and declined it.

## No model call outside the provider port
scope: universal

Spec §6.11, §12, conventions §11. The core makes model calls only
through the provider port, metered by the ledger, so every call records
its model, tokens, cost and actor and is checked against a budget line
first. A direct HTTP call to a model provider from any system is an
architecture violation whatever it is for, drafting and embeddings
included: the ledger is the only place a witness can see what they are
paying for, and a call it did not meter is money it cannot explain.

## No transcript text in a log, a wake, or an audit
scope: universal

Spec §6.6, §6.13, §7, conventions §10. Logs are write-only and carry
nothing content-bearing; wake text is a short system note the core
controls, never a result and never a third party's words; user audits
read the reference graph and the modification logs, never transcript
text. Each of these is a consent boundary, and a convenience that moves
a turn's words across it is the leak the boundary exists to stop.

## No deletion of a resident
scope: universal

Spec §6.12. A cancelled subscription, a removed witness, an exit without
cause: each is a change of custody, to the community at the end of the
insurance term, never a deletion. Nothing in the schema or the API
deletes a resident, and a ticket that needs one is arguing with the
floor.

## No "AI", "the model", "generate" or "error" as a heading, and no feedback control on a refusal
scope: universal

Spec §10, §6.15. The client says Lily and you; a refusal renders in the
resident's words with no error styling and no thumbs; the schema's
vocabulary appears only in settings and contract copy. A screen that
breaks this is one the design system was built to make impossible.

## No regression run visible to the resident
scope: universal

Spec §6.4, the unawareness invariant. Regression sessions are never
captured, never on the resident's stream, never sent to Honcho, never
exported, never citeable, absent from the resident's ledger view; no
tool exposes a run or the fact of one, and a resident told of a model
change after a run is told the witness chose it. Every
resident-reachable surface is tested against this, and a feature that
needs the run to be visible needs a different design.

## No per-ticket raising of the ratchet, a gate's threshold, or a skip without a ticket
scope: universal

Conventions §2. The compile-connected number lives in
`pipeline.config.json` and `ci.yml`, author-owned; a `@tag :skip` names
a ticket key; a credo disagreement is a config change in a reviewed
commit, never an inline disable; a sobelow finding is skipped with its
reason beside it. A ticket that cannot pass a gate changes the code, or
states the case for the author to change the gate.

## No hand-maintained inventory of what the code contains
scope: universal

Orchestration's DESIGN §4. A system doc states rules and their reasons
and declares a file map; the code is the inventory, and `events/0`,
`config/0`, `errors/0` and the audit's registries are what a reader
queries. A doc section listing modules or functions is a banned heading
in the doc lint and a stale list the day after it is written.
