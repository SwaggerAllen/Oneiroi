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

## Round 7: CI and invariants (2026-10-26)

Lifted from Catapult's conventions and CI into `design/conventions.md`:
the gate set as one block held identical across CLAUDE.md, ci.yml and
qualityGates; the ratchet at zero in author-owned files only; the
component behaviour and registries; the naming spine; the purity floor
with an AST audit and a self-pruning escape comment; immutable event
shapes with upcasters and fixture logs; properties as the floor; no
network in CI; `:live` as a cadence; structural coverage; recorded
fixtures; cost assertions; write-only logs; wrapped secrets. Inverted:
the core makes model calls, through one metered port. Oneiroi's own:
tenancy (RLS on every projection, scoped Repo), the consent boundary and
the unawareness invariant as tests, actor and note on every event,
bounds tagged in the settings module, prompts as files. Spec §12 now
names the gates and the layers.

## Round 8: the P0 plan (2026-10-26)

- P0 is sequenced in `design/p0-plan.md`: four attended steps (skeleton
  and substrate, the persistence spine, the client and SDK skeletons, the
  orchestration hookup), then three pipeline-delivered tickets (identity,
  resident, records) after a verification ticket.
- Catapult's `components/daedalus` is Apache-2.0 and is lifted as a path
  dependency rather than rewritten; the SDK consumes the same package.
- The event store runs on Postgres in test as well as production; the
  in-memory adapter would be a fake that disagrees with the real store.
- The export never carries the resident's uuid, so a rebuild can be a new
  resident and still re-export byte-identically up to the `Imported`
  event.
- Open for the author: the Postgres major, secrets at rest (`cloak_ecto`
  recommended), the GitHub provider's credential in P0 (a steward-supplied
  fine-grained token recommended), the Linear team key, whether identity
  goes through the pipeline.
- Settled the same day: all of the above as recommended, with two
  changes. Identity is written attended (P0.4, ahead of the hookup so the
  project is never parked for its own authors), and the tracker is a
  project under the existing `ORC` team rather than a new team. The
  substrate question was put as "does lifting chain us to Catapult's
  lifecycle": no, because it is a copy with no upstream, and the plan now
  says so.
- Working agreement from the author, after two design PRs conflicted on
  this file: one PR open at a time per repository, however large it
  grows. New work in a repository is stacked onto its open PR rather
  than held for a second one, so a session never waits on a merge to
  land the next thing, and a PR in another repository (the orchestration
  touch-ups beside P0's) may sit open alongside. The rule is against
  splitting one repository's work into PRs that could have been one.

## Round 9: the rest of P0 in one pass (2026-10-26)

- P0.2, P0.4, P0.6 and P0.7 were built attended in one branch on the
  author's ask ("knock out the rest of P0 in one go"), with P0.5's
  repository artifacts beside them; the account-side hookup steps are
  `SETUP.md`'s. The plan's P0.6 and P0.7 tickets are therefore not the
  pipeline's first work; the verification ticket is.
- Secrets at rest are `Oneiroi.Apsu.Vault` (AES-256-GCM over
  `:crypto` under `APSU_VAULT_KEY`), not `cloak_ecto`: the
  dependency arrived with two open advisories and no fixed release, and
  `mix deps.audit` refused it. The plan's decision 4 records the change.
- The export's own bookkeeping (`ExportWritten`, `BackupCommitted`) is
  `export: false`, and the export line's `sequence` is a dense ordinal:
  measured, exporting the bookkeeping made every nightly backup commit
  again forever, and the stream version left gaps a rebuild closes.
- An imported stream is a new resident with the source's slug suffixed
  by its new id's first eight hex digits and no remote; the projector
  reads `imported` from the replayed events' metadata.
- The ratchet stays at zero by construction rather than by concession:
  `Oneiroi.Event` split from its codec, and the router and projection
  macros name every module as an atom. The alternative, raising the
  number for Commanded's macros, was measured at fifteen edges and
  declined.
- The two database roles are one credential and `SET ROLE`; the Render
  measurement the plan asked for is not needed by that shape and is
  recorded as not taken.
- Twelve stubs, not fourteen: Render's previews retire the Pages pair.

## Round 10: dates, figures, the journal's day row, behaviours (2026-10-27)

A brainstorm with the author, settled into the spec in the same sitting.

- **Dates are rows and a countdown is never written** (§6.7, F56):
  David recomputed "days to the application" daily and left stale
  numbers in every file that had copied one. The date is the record; the
  index derives the countdown on the turn that reads it; associations
  are taggings and citations, not an edge table.
- **Figures generalise counters** (§6.13, F57): one row kind for a
  counter (the fold of increment events) and a countdown (derived from a
  date), both citeable and taggable, both what the "number it was not
  shown" rule resolves against.
- **The journal's day row is the schedule's to create** (§6.5, §6.7):
  made at the day's first check-in, so a day never written is a visible
  row rather than an absent file, and reads go by day key.
- **Behaviours** (§6.3, F55): how the resident tends to act, as rows it
  owns, with a trigger, a stance and enactments tagged on turns; two
  scores kept apart (habit strength a decayed measurement, connection
  strength a decision trace of pins and affirmations); the brain
  self-tags enactments and the nightly memory pass only proposes;
  context assembly retrieves by trigger and the brain chooses. The author
  weighed putting choice in the memory agent and declined it because the
  memory agent lacks the brain's identity; the split is retrieval in
  memory, choice in the brain. Trials are derived from behaviours (§6.4),
  so a model change is graded on whether the character carries over.
- Placement: behaviours in P1 with memory and the brain; dates, figures,
  the day row and the derived trials in P2.
- A name for the behaviours part was offered and not yet taken: *ethos*,
  Greek for character, which Aristotle derives from habit (Nicomachean
  Ethics II.1). It is the author's to name, as every name is.

## Round 11: the last names (2026-10-27)

- Ethos names the behaviours part under kumbukumbu, as offered in round
  10 and taken by the author.
- Proteus names the bridge to Honcho (the shape-changer who knows
  everything and answers only to the one who holds on), chosen over Janus
  and Argus; Apsu names the platform (the deep the earth floats on, and
  Enki's house, so the provisioner's waters and the platform are one
  place), chosen over Yggdrasil after Oceanus was set aside because Gaia
  already has the earth; Daedalus names the substrate (the craftsman who
  came from elsewhere and built the house), chosen over Ptah and
  Hephaestus. The author's rule for the choosing is recorded in
  `design/names.md`: no, or very little, living veneration tradition.
- The code follows the docs as it did in round 9: `Oneiroi.Apsu`,
  `lib/oneiroi/apsu/`, the `APSU_*` settings (the two required ones in
  `SETUP.md`'s manifest and `render.yaml`), `apsu_pubsub`, and
  `components/daedalus` with its app `oneiroi_daedalus`. The `:platform`
  scope and actor kind stay, because there they name the party, not the
  system.
- The client is the one system still named for its function.

