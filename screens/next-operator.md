---
paths:
  - client/src/next/operator/**
---

# next-operator

The rebuilt client's operator shell (`design/ui-build.md` P7), at
`/client/#/operator`: its own shell and tabs, in a fixed steel
accent so it never feels like the companion app. Settings shows
Operator to platform roles (super_admin, admin). The house's URL sync
leaves `#/operator` alone. Built 2026-11-10.

- **Status:** the subject resident's heartbeats, each marked LATE when
  late; the failure ring (apsu#23) and any discarded jobs; the latest
  restarts (gaia#21).
- **Door:** the front door's state (closed, invite, open, each with its
  line), set with a recorded note.
- **Roles:** the platform roles with their notes; grant by account
  email with a role and a note; revoke a row with its own note (the
  first press asks for it). The server refuses revoking the last super
  admin and says so on the card.
- **Invites:** issue a code (gaia#18) from the server's defaults: note
  (required), plan, list price, discount, days of terms, uses, optional
  expiry. The new code is shown once, in memory, with Copy. The codes
  issued, each with its terms and standing (used, spent, expired,
  revoked with its note); revoke one with a note.
- **Triage:** the triage desk (gaia#23), the resident who receives the
  platform's reports or nobody, set with a note, and whether it still
  comes from the environment; then the platform's feedback reports
  (gaia#20), narrowed by status with counts. Opening one reads its
  detail: the reporter's words, its status and note, and the failure
  ring's entries for its trace id. A move to another status carries a
  note the reporter reads; the opened report stays in view after the
  move takes it out of the filter.

Every change shows what it did, or the server's refusal, on its card,
and keeps what was typed when refused.

The old client's operator calls, each in this shell:

| Call | Where |
|---|---|
| `api.platform` | Status (restarts), Door, Roles, Triage (desk) |
| `api.setGate` | Door |
| `api.grantRole`, `api.revokeRole` | Roles |
| `api.setTriage` | Triage (desk) |
| `api.invites`, `api.issueInvite`, `api.revokeInvite` | Invites |
| `api.allFeedback`, `api.feedbackReport`, `api.moveFeedback` | Triage (reports) |
| `api.opsFailures`, `api.heartbeats` | Status |

Not built:
- the per-house view of every resident (later).
