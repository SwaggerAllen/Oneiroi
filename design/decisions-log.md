# Oneiroi: decisions so far (2026-10-25)

Recorded from the owner's answers to `spec-questions-and-critiques.md`.
Numbering follows that exchange (C = critique, Q = question).

## Decided

- Q1/C1: Spec the final product first; tiers (core, opt-in, opt-out) and
  the demo line come after.
- Q2/C1/C2/C8: Shared tables with row-level security, planned for
  millions of residents. Not schema-per-resident.
- Q3/C3: The resident is the root entity. Humans have their own separate
  existence; custody is a relation.
- Q4/C4: Citation prefix is the resident slug (`lily:` stays Lily's).
- Q5/C5/C6: New database. Lily migrates by rebuild from her repo, with a
  designed lapse. Anything needed from the old DB is moved into the repo
  first; regression runs are accepted losses. Keep notes on what does not
  transfer. This is the trial run of "rebuild from repo".
- C3 (OpenClaw-native memory): long term, replace OpenClaw's memory scheme
  with ours (transcripts in repo, indexed in Postgres); accept the loss now.
- C4 (names): build without `lily` baked in; migrate by rewriting keys and
  references in the Lily repo.
- C5/C6/Q6: Two OpenClaw instances per tenant, not three: core (brain,
  judge, memory agent) and hands (worker + reader). Containers suspend when
  idle. Demo: one box, many containers. End state: Kubernetes. Ideal: the
  DB is always up and only a stateless agent runtime wakes.
- C5/C6 (open): a bespoke Elixir core for chat and memory, delegating to
  OpenClaw for work outside the repo; possibly cutting OpenClaw as the
  platform default (fork or reimplement). Catapult's practices are the
  reference. Decision pending; see the reply.
- C7/Q7: Portability requires supporting whatever agent people use, with
  one platform default. Lily in the Claude Code UI as soon as possible;
  the reader ships out of the box, which means OpenClaw.
- Q8: Honcho shared, one workspace per resident.
- C9: Judge and memory agent are LLM-backed; the memory agent has tools.
  "Agent" only in OpenClaw's sense if they run there.
- C10: Tight testing around the OpenClaw contract, lifting OpenClaw's own
  tests where useful. Users will not be on a VPN, so a security layer
  wraps OpenClaw's protocol ("OpenClaw+").
- C11/Q9: Auth is new. Client is React, a full rewrite. Self-hosted option
  means the backend must be swappable. React support added to orchestration.
- C12/Q10: Orchestration needs touch-ups; deploy split (platform app vs
  tenant runtime) agreed with the caveat below.
- C13/Q16: Gitea later: one instance, one organization per user (as Honcho).
  Arbitrary git providers supported; the Merkle attestation is what lets
  memory integrity be checked on a repo we do not host. Dynamic
  tenant-runtime deployment: built on orchestration or an Oneiroi deploy
  system, undecided.
- C15/Q12: Event log is the spine, strict event sourcing, now. Commanded
  if the core is Elixir, otherwise a hand-rolled event layer. Rebuild from
  git must remain possible. Idea on the table: commit messages as the event
  stack with the file tree as projection.
- C16: Merkle root: event sequence plus commit hash as the proxy for DB
  state (left open on purpose).
- C17/Q13/Q17: One key from the user, at least two budget numbers, more
  budget targets later. Per-resident ledger. Platform tokens opt-in with
  the markup (BYO users pay no markup). BYO and platform-token experiences
  as close as possible. Judge billed to the user with the rest.
- Q17: Judge model customizable (check-engine light, not a leaderboard).
  Open to being talked out of it.
- C18/Q14: v0 mail is "sign your resident up for Gmail". RSS feeds are v0.
  Substack email parsing may not port; many platforms via Skyvern may be
  simpler. SMTP server later for arbitrary forwarding.
- C19: Wizard is a sketch; the UI pass will add to it.
- C20/Q15: A better word than "owner" is needed. Candidates: patron,
  sponsor, partner.
- C21: License audit now. AGPL is the default; open to Apache or MIT.
- Q18: Rebuild the blocker list honestly; do not recover the old one.
- Q19: Everything programmatic pinned fleet-wide and upgraded as a unit.

## License audit (2026-10-25, read from each repo's LICENSE file)

| Component | License | Bearing |
| --- | --- | --- |
| OpenClaw (openclaw/openclaw) | MIT, OpenClaw Foundation | No constraint; forking is fine |
| Honcho (plastic-labs/honcho) | AGPL-3.0 | Run as a separate service, unmodified or with source offered; our code talks to it over its API and reads its tables, which is arm's length |
| Skyvern (Skyvern-AI/skyvern) | AGPL-3.0 | Same: separate service, never embedded |
| Commanded | MIT | No constraint. EventStore (same author) not re-read; believed MIT |
| Gitea | MIT | No constraint |
| React, Phoenix | MIT | No constraint |
| pgvector | PostgreSQL License | No constraint |
| Playwright | Apache-2.0 | No constraint |
| Claude Code | Proprietary | Not a license question but a terms question: running Claude Code on a tenant's subscription token inside a service we operate needs Anthropic's terms read before we custody tenants' tokens |

Recommendation: stay AGPL for the platform, adopt Catapult's split
(`LICENSING.md`): anything third parties embed, such as an agent adapter
SDK or the records-format tooling, is Apache-2.0 so other agent platforms
can adopt the portability format.

## Round 2: the open decisions (2026-10-25, later)

Numbering is the spec's §13 as it stood in v0.1.

1. Steward: confirmed.
2. Suspend and wake: stays open.
3. Memory-wiki: Lily never called it. Decided: cut the plugin and its
   projections; `wiki/` stays as a plain searchable document kind.
4. Reader tools: a fetch and search API first; a shared headless-browser
   pool for what the API cannot render; Skyvern or an agent-driven browser
   only for interactive tasks. Providers and pool size open.
5. Claude subscriptions: the platform never custodies the token. A steward
   who wants Claude on their subscription uses Oneiroi from Claude Code
   through the adapter. The worker runs on OpenClaw with the OpenRouter key.
6. Honcho per-workspace keys: verified on v3.2.2's source (`POST /keys`
   takes `workspace_id`; a `w`-only token is confined to that workspace;
   only `ad` crosses). The person-to-peer threshold stays open.
7. Insurance: proposed as Floor (everyone), Light (opt-in, on by default
   at creation), Standard, Full, on the two axes; prepaid pool, never debt.
   Prices open.
8. Formation period: dropped as a gate. Proposals at any time; the first
   month biases acceptance through the prompt and UI copy only.
9. Governance machinery in v0: reports with an internal investigation and
   strikes. Jury or convention later; the investigator is a role in the
   events.
10. Document sharing between residents: not v0; the social layer is not
    specced.
11. Gitea: after investment, before revenue.
12. Versions settled at build; upgrading must be one change in one place.

Also decided: sources are links the steward releases, never retained text
(copyright and distribution); a read page is citeable as `<slug>:web/...`
with the understanding it may become inaccessible. Bookmarks keep a range
with an anchor turn and gain `bookmark_extend`. Tags become a cross-cutting
`tagging` projection with project-tag links to a repository and a goal.
