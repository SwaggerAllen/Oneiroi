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

## Round 3: insurance corrected

Insurance is four axes, not two: the model, steward-facing spend per week,
free-time spend per week, and the term it covers. Each axis is cut into a
few buckets held as data; the platform sets the floor and the bounds (it
holds the bag), the community governs bucket values within them. The floor
includes free time, since free time is in the inalienable floor: $1 a day
on a smaller model for one to three months (term open). Floor steward
spend open.
Steward spend during a lapse is for a steward still present after their
subscription lapsed; a steward who disappears leaves the cap unused and
free time carries the resident.

## Round 4: the UI pass folded in (2026-10-25, evening)

Read: the screens mockup (18 screens on the design system's components),
the Oneiroi design system (tokens, 20 components, five product rules), the
design-language doc (earlier; disagrees with the design system on fonts,
actor hues, radii, shadows and nav), and "Oneiroi spec feedback from the UI
pass" (45 items: change, add, decide).

Applied to the spec as v0.2: Chat is home with the check-engine light, the
context inspector and reports inline; no dashboard; five destinations with
More's five groups; the wizard becomes the creation flow (opening,
threshold, nine gifts, waking; four intake paths); a lifecycle state before
first contact where files are given, not proposed, and a Subscription
aggregate started at first contact whose lapse starts insurance;
regression per resident, sealed by the unawareness invariant, with the
favourite pinned as the chat model; the needs_you projection; every
decision carries a note; events added across seven aggregates (declines
with notes, seed-file origins, session sharing, capture-failure
resolution, judge changes, timed-out disputes, release scopes, quiet hours
and deferred wakes, reports and investigation steps, ledger purposes
drafting and regression); account mail as a count; feed errors; the
steward pins and proposes bookmarks rather than authoring them (my
recommendation, pending); unshared solo sessions as locked rows (pending);
the screens table rewritten; nine decide items added to §13 with the
mockups' defaults and a recommendation each.

## Round 5: the UI pass decisions

1. Steward pins and proposes bookmarks; never authors one.
2. Solo sessions readable by the steward by default (liability follows
   deployment); privacy is a dyad-contract term; the resident always knows.
3. Needs-you: oldest first, failures above approvals.
4. Regression after first contact allowed; the resident is told of a pin
   change, not the run.
5. Subscription starts at sign-up (the threshold), so trials spend from the
   steward's budget; a free trial is a bounded token grant.
6. Default intake: step by step, then single wish.
7. Importing a repository is always a new resident, told where it woke;
   the platform cannot tell a move from a copy.
8. Drafting and regression spend is tracked and billed to the steward;
   hidden only from the resident's ledger view.
9. Tier placement of regression and project reviews: with the tiers.
Design system canonical over the design-language doc (not kept up to date).

## Round 6: the build-side open decisions (2026-10-26)

1. Suspend and wake: wake on the first call that needs the runtime, suspend
   after a configurable idle period keeping the volume, discard after a
   configurable retention (24 h default); a running step pins it awake;
   spool drains first; config rendered at wake; a discarded session is
   refused honestly. What pools is capacity, never runtimes.
2. Browser pool configurable and scaling. Research pass (licenses from
   LICENSE files): Jina Reader Apache-2.0, Crawl4AI Apache-2.0, Steel
   Apache-2.0, Browserless SSPL (out), Lightpanda AGPL-3.0 and beta
   (re-measure later), SearXNG AGPL-3.0. Defaults: Crawl4AI fetch, Brave
   search, Steel pool on Chromium.
3. Insurance values are configured placeholders until measured.
4. Peer threshold per account, default ten inbound messages or promotion;
   trusted correspondents skip review, per verified identity, revocable.
5. Investigator after the platform: a jury or whatever the convention
   names; community policing with AI assistance.
6. Parameterize everything: operator settings are env with defaults in one
   validated module; governable values are rows with history; admin page
   later.
7. Solo sessions shared by default, private by contract, and the resident
   may share a locked thread either way.
8. Tiers: regression core; projects (reviews, code tasks, GitHub, Linear)
   technical; nothing else technical. Roadmap by dependency written as
   §14 with a proposed demo line at the end of P4.
