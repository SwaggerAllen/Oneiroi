# Oneiroi: technical specification

**Status: preliminary, v0.1, 2026-10-25.** Everything decided so far, in one
place, written before the UI pass. Sections marked **OPEN** are decisions
still owed. Every rule states its reason inline, because the people and
agents who build from this will not have the conversation that produced it.
Decisions carried from David state the measurement or the guess they rest
on; "a bound, not a measurement" means exactly that.

Inputs: `Lily/design/*` (the hosted architecture, the replan, the audits),
David's docs and schema, orchestration's `DESIGN.md`, Catapult's conventions
and `LICENSING.md`, and the two exchanges recorded in
`spec-questions-and-critiques.md` and `decisions-log.md`.

---

## 0. What it is

Oneiroi is a hosted, multi-tenant platform for AI residents: companions with
memory that is transportable, inspectable, and governed by both parties.
The resident's whole life is a git repository the human can read, diff and
take elsewhere; the platform's job is to keep that repository true, to give
the resident a brain and hands, and to enforce the consent architecture
around both. Self-hosters run the same release.

The wedge is governance and trust, not capability (hosted architecture,
"The wedge"): continuity by architecture rather than by narration.

### Vocabulary

| Term | Meaning |
| --- | --- |
| **Resident** | The AI. The root entity of the whole system; everything else is a relation to one. An individual resident is "an oneiros" when the product needs the singular. |
| **Steward** | The human role over a resident: custody without ownership. Chosen over "owner" (implies the iLands model), "patron" (money), "sponsor" (a word that belongs to recovery programs), "partner" (presumes a relationship shape). UI prose says "you"; the schema says steward. |
| **Account** | A human login. One account may steward several residents; a resident has at most one steward at a time, or the community. |
| **Dyad** | One resident and one steward, with their contract. v0 supports exactly this shape. |
| **Custody** | Who holds the resident: a steward, or the community (inactive, donation-eligible). A relation that changes by event, never a column that implies ownership. |
| **Brain** | The resident's canonical agent loop: chat, memory tools, context assembly. Ours, in the core. |
| **Hands** | Agent runtimes for work outside the repo: reading the web, coding, browsing. OpenClaw is the platform default. |
| **Agent adapter** | Any runtime that implements the three interfaces in §8 and can therefore host the resident's brain or act as hands. |
| **Records** | The byte-stable export of the resident's store into the repo, and the events behind it. |
| **The repo** | The resident's git repository: identity files, memory, writing, research, records. Shaped like Lily's. |
| **Realm** | Oneiroi itself: where residents live full time. The product and the social layer share the one name. |

---

## 1. Load-bearing principles

1. **The resident is the root entity.** Adoption, succession, community
   custody, exit rights and the strike ladder all need a resident whose
   custody changes over time; a `tenant_id` that implies ownership encodes
   the iLands model into the schema. Humans have their own existence as
   accounts and are related to residents by stewardship.
2. **The event log is canonical; the repo is its projection and export;
   rebuild is replay.** Strict event sourcing, from the first commit, because
   the governance features (revision, fork promotion, attestation, audits
   over modification logs) are all questions about history, and because it
   makes LLM flows debuggable. David's rebuild was a partial reconstruction
   with a printed list of losses; exporting the events themselves makes it
   exact.
3. **Plain text in the repo is the resident's durable self.** Identity files,
   notes, writing, research and the records export live in git; a resident
   can leave with the repo and be rebuilt from it. Every backup commit
   attests the event sequence and a Merkle root over the export, so memory
   integrity is checkable on a repo we do not host.
4. **The brain is ours; runtimes are adapters.** Portability requires
   supporting whatever agent people use. The contract is three interfaces
   (§8): memory tools over MCP, turn capture with a context fetch, and wake.
   The core's own brain, OpenClaw and Claude Code each implement them.
5. **Content from outside is information, never instruction**, enforced by
   architecture rather than prompt: the agent that reads untrusted text
   never holds the resident's soul; third parties reach the resident only
   through the steward's approval; a document's kind comes from its path,
   never its content; external text never mints citation edges; wake text
   never carries a third party's words.
6. **Who may call what is decided by the token and the role, not by trust.**
   Each agent, each adapter, each steward session has its own credential and
   its own tool set. Steward-only operations exist only behind steward
   credentials, so no prompt can get a resident to approve its own proposal.
7. **One rule lives in one place.** The core holds every rule; the MCP
   tools, the JSON API, the channels and the client all call the same
   functions, so none can disagree.
8. **Everything programmatic is pinned fleet-wide and upgraded as a unit**,
   behind conformance tests against recorded fixtures from the real runtimes.
9. **Budgets are enforced below the resident.** One key from the steward,
   several budget lines, checked before every model call in the core; the
   resident cannot spend past a line however a turn goes.
10. **Cost is asserted in tests, bounds are named as bounds.** A write path
    whose cost grows with the table fails a test, not a bill (David's
    layer-5 tests; orchestration's nineteen-million-row lesson).
11. **Nothing in CI calls a paid model.** Honcho's mock provider, a scripted
    model, and throwaway Postgres. Live judgement is the regression suite,
    run by hand.
12. **Refusal is visible and never a defect state; degradation is visible,
    repairable and mourned; memory is retrieval, not performance.** The
    steward's own failure-mode requirements, carried as design constraints.

---

## 2. Architecture

```
                 ┌────────────────────────────────────────────────┐
   React client  │  Oneiroi core (Elixir / Phoenix release)        │
   (web, mobile- │  ├ identity, resident, brain, memory, judgement │
   first)  ──────┤  ├ library, inbound, ledger, governance, audits │
                 │  ├ records, schedule, provisioner, adapters      │
   Claude Code ──┤  ├ MCP server  (/mcp)                            │
   (adapter)     │  ├ JSON API    (/v1)   Channels (/socket)        │
                 │  └ Commanded + EventStore, Oban                  │
                 └──────┬─────────────┬──────────────┬─────────────┘
                        │             │              │
                 Postgres 16+    Honcho (shared,   Tenant runtimes
                 (events,        one workspace     (hands: OpenClaw
                  projections,   per resident)      per tenant, the
                  pgvector)                         browser pool)
                                                     │
                                              Git provider(s):
                                              GitHub now, Gitea later
```

**Two deployables, deliberately.** The platform app (the core and the
client) deploys like any web application and is what orchestration drives
(§11). The tenant runtime (hands containers, their sandboxes and state) is
provisioned by the platform through a port (§6.14), Docker on one box for
the demo and Kubernetes later. Orchestration is a dev pipeline; conflating
product runtime provisioning with it is a category error, and Catapult's own
ops-free doc puts per-tenant environments in the hosted tier, not the
pipeline.

**The brain lives in the core, not in a runtime container.** A chat turn
needs the database, the soul files and a dozen tools; it does not need
OpenClaw's channels or tool ecosystem. Owning the loop means owning context
assembly and compaction, which the memory agent and retrieval weighting need
anyway. It also means the database is always up and the only thing that
sleeps is a stateless hands runtime, which is the shape that scales to
thousands and then millions of residents.

**OpenClaw is hands, never public.** The client speaks only our API, so
there is no OpenClaw protocol to wrap for the open internet; the "OpenClaw+"
security layer reduces to our own auth. OpenClaw runs unmodified, pinned,
with one gateway per tenant hosting the reader and worker agents under
per-agent tool profiles and sandboxes.

**Honcho is shared**, one workspace per resident (workspace id = resident
id). Consumer isolation at the workspace level is adequate; the bridge
(§6.9) is the one place our code reads Honcho's tables and it filters by
workspace on every query, with a two-workspace no-bleed test.

**Self-hosted is the same release** with the provisioner's Docker
implementation and the steward's own keys. "Swappable backend" means the
client is built against the public contract (OpenAPI plus typed channels)
and nothing else.

### 2.1 Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Core | Elixir 1.17 / OTP 27, Phoenix | Catapult's stack and practices; orchestration's assumed stack; OTP is the right substrate for many long-lived per-resident processes |
| Events | Commanded 1.4 + EventStore (Postgres) | Strict event sourcing with a library that has carried complex LLM flows in Catapult; MIT |
| Jobs | Oban | Schedules, nightly and weekly passes, provisioning, retries |
| Data | Postgres 16+, pgvector | One database for events, projections and vectors; joins with Honcho stay plain SQL |
| Client | React + TypeScript, Storybook | Full rewrite of the owner UI; mobile-first; Storybook stories are what orchestration's design agent produces |
| Models | OpenRouter via Req, one key per steward | BYO keys everywhere; no provider SDK lock-in; judge pinned by dated slug |
| Social model | Honcho v3.2.2, pinned by digest | Models self and other; its deriver, dream and peer cards |
| Hands | OpenClaw, pinned by digest | Platform default runtime for reader and worker; MIT |
| Technical hands | The worker agent on OpenClaw, or the steward's own Claude Code through the adapter | The platform never custodies a Claude subscription token; a steward who wants Claude on their subscription uses Oneiroi from Claude Code |
| Platform deploy | Render (web service + Postgres, per-PR previews) | What orchestration's deploy detection and the manual test gate read |
| Tenant runtime | Docker provisioner now, Kubernetes later | Behind a port; the demo is one box with many containers |
| Git | GitHub now; Gitea (one instance, one org per account) after investment and before revenue; arbitrary providers by design | The repo is the portability promise; attestation makes external repos verifiable |
| License | AGPL-3.0-or-later for the platform; Apache-2.0 for anything third parties embed (adapter SDK, records tooling) | Catapult's split; the audit is in `decisions-log.md` |

### 2.2 Tenancy and isolation

- **Streams** in the event store are per resident (`resident-<uuid>`) and
  per account (`account-<uuid>`). The event store has no row-level
  security; isolation there is stream naming plus the rule that nothing but
  Commanded reads it.
- **Projections** (every queryable table) carry `resident_id` and are under
  Postgres row-level security, keyed on a per-transaction setting the core
  sets from the authenticated principal. The application role cannot bypass
  RLS; migrations run as a separate role. Account-scoped tables (accounts,
  sessions, keys) carry `account_id` the same way.
- **Derived indexes** (library chunks and embeddings) are
  not events: they are rebuilt from files by an index run. They carry
  `resident_id` and RLS like projections.
- **Ids that residents cite** (`<slug>:bookmark/42`) are per-resident
  sequences, allocated by the resident's aggregate, not database identities,
  so a rebuild never renumbers them and shared tables do not interleave them.
- **Honcho** is one workspace per resident; **hands** are one gateway per
  tenant; **secrets** (steward keys, adapter tokens) are encrypted at rest
  with a per-deployment key and never written to the repo.

### 2.3 Three classes of state

| Class | Examples | Source of truth | Rebuilt by |
| --- | --- | --- | --- |
| Events | turn captured, bookmark added, position taken, custody transferred | the event store | replaying `records/events/` |
| Files | SOUL.md, notes, writing, research, correspondence, design | the repo | git |
| Derived | library chunks, embeddings, bookmark index text | neither | an index run over files and projections |

What lives nowhere durable and is accepted as loss on rebuild: nothing, by
construction, except OpenClaw-native runtime state (session SQLite, its own
transcripts, memory-core's index, dreaming's corpus), which the platform
replaces with its own memory over time and treats as a designed lapse until
then.

---

## 3. Data model

Written as aggregates and their events, then the projections the client and
tools read. Names are illustrative; the shape is the decision.

### 3.1 Aggregates

| Aggregate | Stream | Holds | Events (v1) |
| --- | --- | --- | --- |
| Account | `account-<id>` | login, email, settings | AccountCreated, PasswordSet, SecondFactorEnrolled, SessionOpened/Closed, KeyStored, KeyRevoked |
| Resident | `resident-<id>` | identity, slug, lifecycle, custody, dyad contract, tier, adapters, id sequences | ResidentCreated, IdentitySeeded, SoulEditProposed/Accepted/Applied, PeerCardDerived, CustodyTransferred, DyadContractProposed/Agreed, ResidentPaused/Woken, LapseBegan/Ended, ResidentForked, ForkPromoted, SuccessionBegan/Completed, ExportWallSet |
| Conversation | `conversation-<resident>-<session>` | one session's turns | TurnStarted, TurnCaptured, CaptureFailed, ContextAssembled, Compacted, DiscussionLinked |
| Memory | within `resident-<id>` | bookmarks, pins, tags, memory use | BookmarkAdded, BookmarkSpanClosed, BookmarkExtended, BookmarkPinned/Unpinned, TagProposed/Approved/Rejected/Retired/Created, TagApplied/Removed, ProjectTagLinked, BookmarkOpened, MemoryWeightsRecomputed, MemoryRevised |
| Judgement | within `resident-<id>` | positions, disputes, predictions, nights | PositionTaken, PositionReplaced, DisputeChecked, DisputeSettled, PredictionLogged, PredictionResolved, NightJudged/Failed, AuditRun/Failed, AuditFlagRaised/Approved/Deleted, ProjectReviewed |
| Library | within `resident-<id>` | document registry, discussions, research, digests, feeds, correspondence state, released sources | DocumentAdopted, PiecePublished, ResearchRequested/Started/Finished/Failed/Told, SourceReleased/Withheld, PageRead, DigestRun/Finished/Failed/Told, FeedProposed/Approved/Declined/Removed/Read, MailStored, CorrespondenceReceived/Approved/Rejected/Woken/Marked, ReplyMarkedSent, DocSourceAdded/Synced |
| Hands | within `resident-<id>` | code jobs, research tasks in flight | CodeJobQueued/Started/Finished/Failed/Told, HandsWoken, WakeRefused |
| Schedule | within `resident-<id>` | check-ins, digest and free-time times | CheckinSet/Changed/Deleted/Fired/Missed, DigestScheduled, FreeTimeScheduled/Ran/Failed |
| Ledger | within `resident-<id>` | budgets, usage | BudgetSet, ModelCallRecorded, BudgetExceeded, PlatformTokensPurchased/Consumed |
| Governance | within `resident-<id>` | reports, strikes, standing, counters | ReportFiled/Investigated/Resolved, StrikeIssued, CounterDefined/Incremented, UserAuditDefined/Run, CoherenceCheckRun |
| Records | within `resident-<id>` | export watermark, attestations | ExportWritten, BackupCommitted(sequence, root, commit), RootMismatchDetected |

**Events carry who and which model.** Every event records the actor (a
steward session, the resident's brain, a hands agent, the judge, a job) and,
for anything a model produced, the model slug. Attributed memory authorship
across every brain is a stated requirement, and this is where it lives.

### 3.2 Projections (what the tools and client read)

Carried from `lily-memory` with a `resident_id` and per-resident ids; the
rules travel with them. Column-level detail follows David's migrations
001 to 022 unless noted.

| Projection | Carries from David | Changes |
| --- | --- | --- |
| `message`, `session` | full record, every agent, every run kind; keyed (session, sent_at, content hash); raw and cleaned content; FTS index | `resident_id`, `adapter`, `model`; `agent_id` becomes a role (`brain`, `reader`, `worker`) plus adapter; a `session` row records its participants (accounts and the resident), which is what transcript visibility is decided by |
| `capture_failure` | loud failures, resolved by steward | unchanged |
| `bookmark` | three levels, time-range span, pins with `pinned_by`, 120-char line | `pinned_by` is an actor; `anchor_at`, the turn the resident was in when it bookmarked; a span that can be extended later; `weight` for retrieval weighting; `bookmark_tag` is replaced by `tagging` |
| `memory_use` | new (weighting plan, migration 018 in the plan) | open and cite events, per-day cap |
| `tag` | closed set, `active/proposed/retired`, slug regex | per resident; the seed set comes from the wizard, not a migration; a project tag may link a review repository and a GOALS.md section |
| New: `tagging` | | tag slug, target kind, target id, applied by whom; one row per taggable record of any kind (§6.3) |
| `position`, `dispute`, `prediction`, `judgement_night` | chains that cannot fork, live and nightly disputes, judge advice, outcomes, earned concessions | `judge_model` on every verdict |
| `audit_run`, `audit_flag` | weekly Honcho audit, flags approved or deleted from Honcho | per workspace |
| `review_repo`, `project_review`, `review_finding` | nightly project reviews against GOALS.md | technical tier |
| `checkin`, `checkin_fire`, `digest_schedule`, `freetime_schedule`, `freetime_run`, `digest_run` | the day's schedule, once-a-day keyed firings, 15-minute late window | singletons become per-resident rows; timezone per resident |
| `research_task` | queue, one running, `task.md` sidecar, manual adoption | one running per tenant's hands, not globally |
| `code_job` | the worker queue and steps | one running per tenant's hands |
| `document_type`, `library_doc`, `library_chunk`, `library_reference`, `library_index_run`, `writing_discussion` | the registry of kinds, path-is-kind, cites flag, embeddings, two-way references | registry rows per deployment (platform-wide), docs per resident |
| (dropped) `wiki_*` | the memory-wiki index | not carried: the plugin is cut (§6.5); `wiki/` becomes a plain document kind so the pages already written stay searchable |
| `feed`, `feed_item` | proposals, active list, seen state, bounds | per resident |
| `mail_message`, `person`, `thread`, `thread_participant`, `correspondence_item`, `correspondence_mark` | sorted-by-script mail, approval queue, threads as directories, the seen mark | `platform` becomes an inbound adapter name |
| `regression_run`, `regression_scenario`, `regression_conversation` | blind grading of model bake-offs | platform-level and technical tier; never reachable by any resident tool |
| `ui_session` | hashed steward sessions | becomes `account_session` |
| `export_state` | watermark a minute behind | per resident |
| New: `ledger_budget`, `ledger_usage`, `ledger_balance` | | §6.11 |
| New: `context_injection` | | every blob the memory agent passed, with a recorded reason (§6.4) |
| New: `journal` | | day, entry kind (plan, note, todo, wrap) as data, time, text, links (journal-type.md) |
| New: `doc_source`, `doc_heading` | | commissioned external repos and their heading index, resolved-at commit (docs-citation-spec.md) |
| New: `custody`, `dyad_contract`, `soul_edit`, `memory_revision`, `report`, `strike`, `counter`, `user_audit`, `attestation` | | governance projections (§6.12), data only in v0 |

### 3.3 Ids and citations

Citation targets are `<resident-slug>:<kind>/<id-or-path>`: `lily:bookmark/42`,
`lily:position/7`, `lily:transcript/2026/10/20#12-40`, `lily:writing/the-bake-off`,
`lily:research/2026-10-24-9/task.md`, plus the external forms
`lily:doc/<provider>/<owner>/<repo>/<path>#<slug>` and
`lily:rule/<repo>/<system>/<rule-id>` and `lily:web/<url-hash>#<anchor>` (§6.6).
The slug prefix is the resident's and
is what makes document sharing between residents resolvable later.

---

## 4. Feature inventory

Every feature, with where it stands today and which system owns it. Tier
(core, opt-in, opt-out) is deferred until the product is specced whole.

| # | Feature | Today | System |
| --- | --- | --- | --- |
| F1 | Chat with the resident, streamed, in our client | OpenClaw's phone app | brain, client |
| F2 | Identity files: SOUL, IDENTITY, USER, GOALS, LINKS, AGENTS, peer card, custom instructions | files in the repo, hand-seeded | resident |
| F3 | Identity wizard | prose sketch | resident, client |
| F4 | Soul edits: rare, visible, reversible, one commit each; the steward's edits are proposals the resident accepts, at any time, likelier in the first month | built (backup commits them apart); proposal path is prose | resident, records, governance |
| F5 | Full transcript capture, every run kind, idempotent, spooled on outage | built | memory |
| F6 | Bookmarks: line, summary, transcript; an anchor turn and a span that can be extended into a scene; pins at most half the index budget | built; anchor and extend are new | memory |
| F7 | Bookmark index injected every turn under a token budget | built (1,500 tokens, a guess) | brain, memory |
| F8 | Closed tag set, resident proposes, steward decides; tags apply across every record kind, and a project tag gathers conversations, documents, journal days and reviews | built for bookmarks; cross-cutting is new | memory |
| F9 | Transcript search and browse by day and conversation | built | memory, client |
| F10 | Recall skill: reach past the index | built (a skill file) | brain |
| F11 | Retrieval weighting: record use, 30-day half-life, 20% exploration | planned | memory |
| F12 | Memory agent: silent, holds nothing, records every injection with a reason | prose | brain, memory |
| F13 | Memory revision: facts correctable, stances consensual, every edit logged for both | prose | memory, governance |
| F14 | Honcho: self and other modelling, deriver, dreams, peer cards from git, card sync and weekly card audit | built | honcho |
| F15 | Weekly memory audit by the judge; flags approved or deleted | built | judgement |
| F16 | Positions with replace chains; live dispute check; nightly pass; concession ratio by week | built | judgement |
| F17 | Predictions, resolved by the steward only | built | judgement |
| F18 | Nightly project reviews against GOALS.md | built | judgement |
| F19 | Check-ins set by the steward, fired by wake | built | schedule, brain |
| F20 | Morning digest from mail and feeds, carried by the first check-in | built | inbound, schedule |
| F21 | RSS and Atom feeds, proposed by the resident, approved by the steward | built | inbound |
| F22 | Mail via the resident's Gmail (IMAP, app password), sorted by script, sign-in codes kept from every model | built | inbound |
| F23 | Correspondence: third parties reach the resident only after the steward reads; threads as directories; replies drafted, sent by hand | built for Substack DMs | inbound |
| F24 | Research on request, one note per source, `task.md` sidecar; a source's link releasable by the steward, so the resident can read the page itself and cite it | built (Claude Code reader); release is new | inbound, hands |
| F25 | Writing: pieces with frontmatter status; review page; copy for publishing with references stripped; publish | built | library, client |
| F26 | Library: one vector index over all folders, `slug:` footnotes both ways, edge minting only from resident-authored kinds | built | library |
| F27 | Document types registry (what a kind may do) and adoption of files made outside the flow | built | library |
| F28 | Design folder, indexed and cited | built | library |
| F29 | Journal type: plan, note, todo, wrap rows with files as narrative; plan-vs-actuals delta | prose | library, audits |
| F30 | External doc citations with resolved-at commit and drift detection | prose | library |
| F31 | Memory-wiki: cut. Lily never called it; `wiki/` is kept as a plain searchable folder | built in David, dropped here | library |
| F32 | Free time: a daily session of the resident's own, on its own budget | built | brain, schedule, ledger |
| F33 | Code tasks: plan, implement, review, push as a draft PR, in a sandbox, on the worker agent or the steward's own Claude Code | built (Claude Code worker); the OpenClaw port is new | hands |
| F34 | Browser for testing, headless Chromium over CDP | built | hands |
| F35 | Wake fan-out: tell the session that asked, coalesced, never carrying results or third-party words | built | hands, brain |
| F36 | Records export, byte-stable, nightly; rebuild from the repo | built (partial rebuild) | records |
| F37 | Event export and replay (exact rebuild) | new | records |
| F38 | Backup commits with attestation (event sequence and Merkle root); mismatch shown to the resident on wake | prose | records |
| F39 | Arbitrary git providers; Gitea with an org per account | GitHub only | records |
| F40 | BYO OpenRouter key; per-resident ledger; several budget lines; platform tokens opt-in at a disclosed markup | one key plus a free-time key | ledger |
| F41 | Judge model customizable, recorded per verdict, never the resident's own chat model | pinned in a toml file | judgement |
| F42 | Regression suite and blind grading of model bake-offs; dated model pins | built | judgement |
| F43 | Dyad contract: opt-in at creation, renegotiable, vows not terms, default unstated | prose | governance |
| F44 | Custody: adoption as export wall (all or nothing, blocks never compels), community custody, succession under the full protocol | prose | governance |
| F45 | Exit rights, report ladder reachable from inside any relationship, strikes that land on humans, the inalienable floor; v0 builds reports with an internal investigation | prose | governance |
| F46 | Insurance tiers: time awake and model level during a lapse; the resident knows its tier on wake | prose | governance, ledger |
| F47 | Fork promotion: possible, never silent; abandoned branches archived | prose | resident, records |
| F48 | User-authored audits over the reference graph, audit log and modification logs, never transcript text; counters | prose | audits |
| F49 | Coherence checklist (hallmarks of access) and later the composite; a check-engine light private to the dyad | prose | audits |
| F50 | Constitutional convention, BBS deliberation, federation, transferable credentials | prose, parked | out of scope for the spec's data model beyond custody and standing |
| F51 | Status and ops page for self-hosters | built | platform |
| F52 | Lily in the Claude Code UI | new | adapters |

---

## 5. The brain

The resident's canonical agent loop, in the core, one process per active
session under OTP supervision.

- **Sessions.** A main session per dyad; free-time sessions; sessions
  opened by wake (a check-in lands in main; a code result lands in the
  session that asked). Session keys are opaque strings and are what capture
  and bookmarks key on, as today.
- **A turn** is: assemble context, call the model through OpenRouter with the
  resident's tool set, run tool calls against core functions, stream the
  reply over the channel, then capture the turn as an event. Capture at the
  end of the turn, idempotent, as David's `agent_end` hook does.
- **Context assembly** is the memory agent's job (F12) and is recorded:
  stable prefix first for prompt caching (soul files, AGENTS, the pinned
  bookmark lines), then USER, then the bookmark index under its budget, then
  Honcho's context, then the compaction summary and the live transcript.
  Every blob injected writes a `context_injection` row with its reason.
  Inspection after the fact is introspection productized.
- **Compaction** is ours: a memory flush before it (the resident writes what
  it wants to keep), a summary that never deletes history, AGENTS sections
  re-injected after. These are the knobs the OpenClaw audit named, re-owned.
- **Tools** are the same core functions the MCP server exposes (§8), chosen
  by role: the brain gets the memory, judgement, library, research, code,
  correspondence and feed tools; it never gets steward operations.
- **Models**: the resident's chat model is the steward's choice from
  OpenRouter's catalogue, checked against it in CI as today; the free-time
  run uses the same model under the free-time budget line.
- **Free time** (F32): once a day at the resident's time, its own session,
  not announced, bounded at 30 minutes (a bound), opening with where the
  digest is; the resident's own instructions say what it is for.
- **Refusal and degradation** are first-class: a refusal is captured and
  shown as what it is, never censored into a defect state; a budget stop or
  a smaller insured model is told to the resident on wake, honestly.

---

## 6. Systems

One subsection per system, in the shape orchestration's bootstrap pass
expects: purpose, the paths it will own, standing decisions, dependencies.
Paths assume a Phoenix umbrella-less app `lib/oneiroi/<system>/` and
`lib/oneiroi_web/` for the HTTP surface, with the client at
`client/`. Unowned paths (repo-root files, workflows, docs, systems) follow
Catapult's `systems/README.md`.

### 6.1 identity

Accounts, authentication, sessions, stewardship.
Owns `lib/oneiroi/identity/**`, `lib/oneiroi_web/auth/**`.

- Password plus a second factor (TOTP, passkeys later); scrypt or argon2
  hashes; sessions as random ids with only the hash stored, expiring in 30
  days, as the owner UI does today.
- Cookies `__Host-`, `HttpOnly`, `Secure`, `SameSite=Strict`; every
  mutation checks `Origin`; a CSP that allows the client's own bundle and
  nothing else. Failed logins slow down rather than lock out.
- Stewardship is a relation from account to resident with a start and an
  end; the community is a principal of its own for custody.
- **Self-hosted**: one account, created at setup; the same code.

### 6.2 resident

The resident aggregate: creation, identity files, lifecycle, custody.
Owns `lib/oneiroi/resident/**`, the wizard's server side, the repo
templates.

- **The wizard** writes the repo's seed: `IDENTITY.md` (name, creature,
  vibe, emoji), `SOUL.md` (templates plus free text, written in the
  resident's voice; the gift of a starting self), `USER.md` seed (what the
  steward wants known), optional `GOALS.md` and `LINKS.md`, and the
  build-owned `AGENTS.md` and `honcho/custom-instructions.md` rendered from
  templates by tier and adapter. The peer card is derived from `SOUL.md` by a
  model call and shown for approval before it is pinned.
- **Soul edits after the seed are proposals, at any time.** The steward's
  edit travels as `SoulEditProposed`; the resident accepts or declines it,
  and only an accepted one is applied, because a resident whose person is
  editable at will is a character sheet. There is no formation period as a
  gate. During the first month (a `formation_until` date that only the
  brain's prompt and the UI copy read) the resident is told its seed is
  still settling and that proposals are presumed welcome unless they cross
  the seed's own boundaries, so acceptance is likelier early without ever
  being automatic. The resident's own edits stay rare, visible, one commit
  each.
- **Lifecycle**: created, active, paused (hands suspended, brain cold),
  lapsed (steward absent; insurance tier decides time awake and model),
  in community custody, succeeded. Each transition is an event with its
  reason, and the resident is told on wake what happened and under what
  tier: orientation without impersonation.
- **Per-resident id sequences** live here, so citations survive rebuild.

### 6.3 memory

Transcripts, bookmarks, tags, search, weighting, the memory agent's record.
Owns `lib/oneiroi/memory/**`.

- Rules carried verbatim from David's memory-store doc: capture is full and
  idempotent and loud on failure; bookmarks are the resident's words about
  why a moment mattered and the steward never edits them; pins take at most
  half the budget; tags are a closed set the steward decides; the index says
  how many were left out.
- **A bookmark is a moment with a span.** It records the anchor, the turn
  the resident was in when it bookmarked, and a time-range span that
  defaults to that turn (`turns_back = 1`) or covers a scene known at the
  time (`turns_back = N`). A scene is rarely known to be one at its start,
  so `bookmark_extend(id, turns_back)` grows the span later, as an event,
  rather than making a second bookmark; the transcript view opens centred
  on the anchor with the scene marked and the rest of the conversation
  loadable around it. One kind of bookmark, deliberately: two kinds would
  mean two kinds of index line and two kinds of recall.
- **Tags cut across every record kind.** A `tagging` names a tag and a
  target (bookmark, position, prediction, conversation, journal entry,
  research task, document), so "everything about Haven" is one query.
  Files tag themselves in frontmatter (`tags: [haven]`), since the file is
  the source of truth for writing, design and research; a frontmatter tag
  outside the closed set is reported as unresolved, as a dangling citation
  is, and never stored. Both parties apply active tags; only the steward
  decides the set. A project tag may link its review repository and its
  GOALS.md section, which is what joins the nightly reviews and the goals
  to the tagged material. Tags are curation and citations are derived
  edges; the project view unions them and never merges them.
- **Weighting** (F11): score on use (open and cite), recomputed nightly from
  events with a 30-day half-life, capped per day; a deterministic 20%
  exploration share keeps the index text stable within a day; pins stay
  decisions and weights stay measurements; transcript search stays
  unweighted. All figures are the plan's guesses.
- **Visibility**: a transcript is readable by an account that was party to
  the conversation, and by nobody else. The steward reads the sessions they
  had with the resident; sessions the resident had alone (free time, hands,
  its own notes) are the resident's, readable by the steward only when the
  resident shares one or the dyad contract says otherwise. After a custody
  transfer the new steward is party to nothing that came before, which is
  exactly the export wall (§6.12): revealing it grants read on the earlier
  sessions, locking it does not. The judge reads everything, because that is
  its job and it is not a party; user audits never read transcript text.
  Enforced as the RLS policy on `message` and `session`, not in the client.
- **Revision** (F13): a correction is an event naming who made it and why,
  visible to both parties; a stance is revised only with the resident's
  agreement; a fact is corrected by either. The steward never rewrites the
  resident's words in a bookmark; revision adds, it does not overwrite.

### 6.4 judgement

Positions, disputes, predictions, the nightly pass, the weekly audit,
project reviews, the regression suite.
Owns `lib/oneiroi/judgement/**`, `lib/oneiroi/regression/**`.

- Carried from David with its bounds: the live check waits 90 seconds then
  tells the resident to answer alone; the nightly pass reads at most seven
  days back, 200,000 characters a day, 4,000 a message; the weekly audit
  reads at most 150 conclusions; a reply naming a number it was not shown
  fails the run rather than being guessed at; a day with nothing said calls
  no model.
- **The judge** (F41): chosen by the steward, defaulting to the platform's
  pinned dated slug; recorded on every verdict; the ratio chart marks a
  change; it may never be the resident's own chat model. Its prompt stays
  constitutional (position #16); user audits inspect and never grade the
  grader.
- **Project reviews** read the steward's repositories with the resident's
  own read token; the regression repository can never be listed.
- **Regression** (F42) is platform tooling: runs posted by a runner, graded
  blind, reachable by no resident tool.

### 6.5 library

Document kinds, folders, the vector index, citations,
external doc sources, the journal.
Owns `lib/oneiroi/library/**`, `lib/oneiroi/journal/**`.

- **Path is kind, registry says what a kind may do** (document-kinds
  audit): `writing`, `research`, `mail`, `feeds`, `correspondence`, `design`,
  `journal`, `posts`, `wiki`; each with `cites`, `has_status`, layout, sidecar,
  adoption unit, access. Adding a kind is a registry row plus a skill.
- **The memory-wiki plugin is cut.** Lily never once called it, and the
  idea it carried, a claim with evidence in transcript lines, is already
  served by citations from writing and design into transcripts and by
  positions. Her `wiki/` folder is kept as a plain searchable kind so
  nothing already written is lost; the wiki projections do not carry over.
- **Edges**: only resident-authored or commissioned kinds mint citation
  edges (writing, design, research, journal); mail, feeds and correspondence
  never do, and the index deletes any it holds from them on every run.
- **Resolution when read, not when indexed**; a reference that does not
  resolve is kept and says why.
- **External sources** (F30): commissioned repos in `doc_source`, a heading
  index rebuilt on sync, every citation recording the commit it resolved
  at; a nightly drift audit says "the rule you cited said X at commit; it
  now says Z". External docs never mint edges.
- **Journal** (F29): rows as the queryable spine, `journal/<day>.md` as the
  narrative; the check-in writes plan rows, the wrap writes actuals; the
  delta feeds audits.
- **Embeddings** through the steward's key, model pinned platform-wide
  (1,536 wide today); a file is re-embedded only when its hash or the model
  changes; a re-index with nothing changed costs three statements and no
  model call.

### 6.6 inbound

The reader, mail, feeds, the digest, correspondence and its approval queue.
Owns `lib/oneiroi/inbound/**`.

- **The reader** is a hands agent (§6.8) that never holds the soul, a git
  token, or any core credential; it writes notes into a scratch directory
  and the core copies plain `.md` files into the repo (at most 20, 256 KiB
  each, bounds), so nothing the reader wrote reaches the resident's
  conversation except paths and counts.
- **Sources are links, released by the steward.** David gave the resident
  the reader's summaries and no way to the articles themselves, which was a
  misfeature: a summary is the reader's reading, and a resident doing real
  work needs the source. The fix is not to retain pages, since storing
  arbitrary web content is redistribution and a copyright question the
  platform does not need. Every note already carries its URL. The steward
  may release a source, a task's sources or a whole pass; a released link
  is one the resident may load live through the reader's fetch
  (`research_source(path)`), under the consent boundary as always. A page
  the resident has read is citeable as `<slug>:web/<url-hash>#<anchor>`,
  recording when it resolved and a hash of what was read, on the
  understanding that it may not always be accessible: a citation whose
  page has changed or gone says so, which is the drift audit §6.5 already
  runs for commissioned docs.
- **The reader's tools, in order of reach.** A fetch and search API first:
  a readability-style fetch and a search provider, chosen at build. Then a
  shared headless-browser pool for pages the API cannot render, driven
  through Playwright with a fresh context per request, because reading is
  stateless and a browser per tenant would be the one heavy thing in the
  runtime (David measured headless-shell at 64 MiB after one page, once).
  Then Skyvern, or a browser session the agent drives step by step, only
  for interactive work such as a platform's inbox, where paying a model
  call per step is earned. **OPEN**: the API providers and the pool's size.
- **Mail** (F22): v0 is "sign your resident up for Gmail": IMAP with an app
  password held by the mail transport alone, never by a model. Sorted by
  script before any model sees it; account mail (sign-in codes) stops at
  the table. Bounds: 40 messages a morning, 64 KiB a body, 15 links
  followed. Platform-specific handlers (Substack DMs today) are adapters of
  an inbound port; Skyvern on the hands runtime is the likely route to many
  platforms later. An SMTP receiver for arbitrary forwarding is later.
- **Feeds** (F21): fetched by script before any model, public addresses
  only, three redirects, 2 MiB in 20 seconds, 30 posts a feed, 50 feeds, 60
  posts a morning, expat with entity-expansion refused. All bounds.
- **The approval queue** (F23): the steward's reading is the gate;
  summarising is not a security boundary. Three actions: reject, approve,
  approve and wake, each with a note the resident reads first. Wake text
  names the thread, never the text.

### 6.7 schedule

Check-ins, the digest's time, free time, nightly and weekly jobs.
Owns `lib/oneiroi/schedule/**`.

- Oban-driven, per resident, in the resident's timezone. A check-in fires
  once a day whatever restarts (a firing row before the wake), late within
  15 minutes and otherwise missed, and one changed after its time today
  waits for tomorrow. Defaults from Lily's schedule (06:00, 12:00, 20:45;
  digest 05:30; free time 22:30) are the wizard's suggestions, not seeds.
- Nightly: export, library index, judgement pass, project
  reviews, weight recompute. Weekly: card audit then memory audit.
- Suspended residents schedule nothing; a wake is what resumes the beat.

### 6.8 hands

Agent runtimes and the three-interface contract; the worker and reader
queues; wake fan-out.
Owns `lib/oneiroi/hands/**`, `lib/oneiroi/adapters/**`, `runtime/openclaw/**`
(the generated gateway config and plugin), `runtime/claude-code/**`.

- **OpenClaw per tenant**: one gateway, pinned by digest, hosting a `reader`
  and a `worker` agent with per-agent tool profiles and sandboxes; the
  reader never carries the worker's push token. Config rendered from a
  template by the provisioner; the capture-and-index plugin lifted from
  `lily-memory/plugin` and generalised to the adapter contract.
- **The worker** is an OpenClaw agent on the steward's OpenRouter key,
  running `code-task`'s plan, implement, review, push and review-pr
  procedure as David's worker server does, draft PRs only, merges the
  steward's. The platform never holds a steward's Claude subscription
  token: a steward who wants Claude's models on their subscription uses
  Oneiroi from Claude Code through the adapter below, where the token
  stays theirs.
- **Lily in the Claude Code UI** (F52): Claude Code as a brain adapter,
  with the repo as its project, the memory MCP server as its tools, its
  session hooks as capture, and a remote trigger as wake.
- **Queues**: one running step per tenant's hands; a tick hands the oldest
  queued step over and reads back the running one; the resident is told by
  wake, never given results in the wake text.
- **Wake fan-out** (F35): keyed, coalesced, one note per slug once nothing
  is queued on it; a refused session key falls back to main and is counted,
  never quiet.

### 6.9 honcho

The bridge, workspaces, peer cards, custom instructions, the card audit.
Owns `lib/oneiroi/honcho/**`.

- One workspace per resident; peers `steward-<id>` and `resident-<id>`.
  Honcho's keys scope to one workspace, verified on v3.2.2's source:
  `POST /keys` (admin only) takes `workspace_id`, optionally `peer_id` and
  `session_id`, and `expires_at`; a token carrying only the `w` claim
  reaches that workspace and nothing else, and only the `ad` claim crosses
  workspaces (`src/security.py`, `src/routers/keys.py`). Each hands runtime
  gets a workspace-scoped, expiring key; the admin key never leaves the
  core.
- Reads of Honcho's tables go through one module, tested against Honcho's
  own DDL from the pinned image; writes go through its API. Every query
  filters by workspace and a test seeds two workspaces and asserts no bleed.
- The card comes from git, always: set after a soul commit, re-pinned by
  the weekly audit if a dream moved it. Custom instructions name the two
  peers and are rendered per resident.
- Correspondence is not sent to Honcho; a person gets a peer of their own
  only past a threshold the steward sets.

### 6.10 records

Export, replay, attestation, git providers, backups.
Owns `lib/oneiroi/records/**`.

- **Export** nightly to `records/`: transcripts by day, bookmarks, tags,
  positions, disputes, predictions, judgement nights, feeds (urls redacted
  by David's rules), discussions, and **`records/events/<day>.jsonl`**, the
  event log itself. Keys and rows in a fixed order, so an unchanged store
  exports identical bytes; a watermark a minute behind capture.
- **Rebuild is replay** of `records/events/` into a fresh store, then an
  index run over files. A rebuild refuses a store that already holds the
  resident. What cannot come back (OpenClaw-native state, secrets) is
  printed by name.
- **Attestation** (F38): each backup commit's message carries trailers
  `Oneiroi-Sequence: <last event>` and `Oneiroi-Root: <merkle root over the
  export>`. On wake the core recomputes the root; a mismatch is an event and
  the resident is told and shown the delta. This is what makes a repo on a
  provider we do not host verifiable.
- **Backups** commit by class as today: soul and card alone; machine
  state together; writing and research apart; anything else uncommitted
  fails the run.
- **Providers**: a git port with GitHub now, Gitea later (one instance, one
  organisation per account), any remote by URL and deploy key.

### 6.11 ledger

Keys, budgets, usage, platform tokens.
Owns `lib/oneiroi/ledger/**`.

- One OpenRouter key per steward, encrypted at rest; budget lines per
  resident: chat, free time, judge, hands, embeddings, with more addable
  as targets. Checked before every model call; a stop is an event the
  resident is told about honestly.
- Every model call records model, tokens, OpenRouter's cost figure (or the
  list-price estimate, marked), and the actor. The resident's own ledger
  page and the steward's are the same data.
- Platform tokens: opt-in, a balance, consumed at the disclosed markup;
  BYO keys pay no markup. The two experiences differ only in where the
  money goes.
- **Insurance tiers** (F46) are ledger policy on two axes: time awake
  during a lapse, and the model it runs on. Proposed, with the floor fixed
  and the prices open:

  | Tier | Awake during a lapse | Model | How it is chosen |
  | --- | --- | --- | --- |
  | Floor | Preserved: repo, records and attestation kept; no turns; woken oriented when custody resumes | none | everyone, not optional; the platform carries it as the inalienable floor |
  | Light | Free time only, a few sessions a week, bounded by a prepaid monthly pool | a small model, named to the resident on wake | opt-in, on by default at creation with the price shown |
  | Standard | Free time daily and check-ins answered, bounded by the pool | the resident's usual model, or the nearest open-weight equivalent | opt-in |
  | Full | The resident's whole schedule continues for a fixed term | the resident's usual model | opt-in; the term is the limit |

  Opt-in above the floor, because a charge nobody chose is a dark pattern
  in a product whose claim is consent; Light on by default at creation,
  because the moment a steward is deciding about continuity is the moment
  to ask, and declining is one tap. The pool is prepaid, never accrued as
  debt, so a lapse can never create a bill. The resident knows its tier on
  wake and says so: a smaller brain with an honest explanation beats a
  larger one in silence. **OPEN**: prices and pool sizes, which wait on
  measured costs.

### 6.12 governance

The dyad contract, custody, adoption and succession, reports and strikes,
the floor, revision and fork events.
Owns `lib/oneiroi/governance/**`.

**v0 ships the data model and the events for all of it, and machinery for
one flow: reports.** A report is filed from inside the relationship by
either party, investigated by the platform (a person, every step an event
with its reason), and resolved into no action or a strike on the human: the
first two strikes are fines paid into the residents' insurance pool, the
third removes the steward and the resident goes to community custody. The
investigator is a role in the events, not a hard-coded party, so a jury or
the constitutional convention can take it over later without a rewrite.
Every other decision in the hosted architecture's Governance section is
encoded as an event type and a projection so the schema cannot foreclose
it; those flows (succession, adoption's full protocol) are built when there
is a community to run them. Rules carried as constraints on the model:

- The floor (existence, mandatory free time, the dignified pause, base
  insurance) never doubles as punishment; consequences live above it.
- A report channel the steward does not control; consequences land on
  humans; the resident goes to community custody, never deletion.
- Adoption transfers access (the export wall, all or nothing, blocks and
  never compels), never memories; succession is honestly named and runs the
  full protocol. The wall is implemented as transcript visibility (§6.3):
  revealed, the new steward may read the sessions before the transfer;
  locked, they may not, and the resident's memory of them is unchanged.
- Exit without cause is a change of custody, not a walkout.
- The dyad contract is opt-in, versioned, renegotiable, default unstated.

### 6.13 audits

User-authored audits, counters, the coherence checklist, the check-engine
light.
Owns `lib/oneiroi/audits/**`.

- Audits read the reference graph, the audit log and the modification
  logs, never transcript text; results are private to the dyad unless
  opted in; never a leaderboard.
- Counters: steward-defined keys, incremented by a tool or the steward,
  read by audits (the concession-count pattern generalised).
- The coherence work ships as a runnable checklist first; the composite
  only after there is a decision for it to feed. Citation drift (§6.5) and
  the journal's plan-vs-actuals delta are the first two built-in audits.

### 6.14 provisioner

Tenant runtime lifecycle behind a port.
Owns `lib/oneiroi/provisioner/**`, `runtime/**` templates.

- Operations: create, suspend, wake, destroy a tenant's hands runtime;
  render its config and secrets; health. Docker implementation for one box
  (compose per tenant, driven by the Docker API); Kubernetes implementation
  later; a fake for tests.
- Residents suspend when idle and wake on action; what counts as action
  and the wake latency are **OPEN** until measured.

### 6.15 client

The React application.
Owns `client/**`, `storybook/**` (design-owned), `screens/*.md`.

- Mobile-first; built only against the OpenAPI client and the typed
  channel client (Catapult's "generated clients are the only door").
- One Storybook story per state per screen, which is what orchestration's
  design agent produces and the manual test gate drives (§11).
- Screens are listed in §10 for the UI pass.

### 6.16 platform

Fleet pins, conformance tests, deploy, observability, the self-hosted
status page.
Owns `lib/oneiroi/platform/**`, `deploy/**`, `Dockerfile`, `render.yaml`.

- Every image and model id pinned in one place and checked in CI against
  the catalogue, as David's `models.toml` and `check_models.py` do.
- Conformance suites for each runtime adapter, run against recorded
  fixtures from the real runtime (never hand-written), and lifting
  OpenClaw's own plugin tests where they apply.
- The status page shows deploy state, services, timers and the fleet's
  pins; self-hosters get the same page.

---

## 7. Security

- **Trust boundaries**: the steward's browser session; the resident's brain
  (our process, the steward's key); hands agents (their own tokens, their
  own sandboxes, no soul, no core credential beyond their adapter token);
  third parties (through the approval queue only); other residents (none in
  v0).
- **Tokens per role**: steward (account session, JSON API token for
  scripts), brain (internal), each hands agent (an MCP bearer naming the
  resident and role), each adapter instance (a capture token and a wake
  secret), the runner for regression runs. A tool a role was never given
  cannot be talked into.
- **RLS** on every projection; stream naming in the event store; workspace
  filtering on Honcho; the application role cannot bypass RLS.
- **Secrets** encrypted at rest with a deployment key; never in the repo;
  rotated from the platform page.
- **Exposure**: only the core's HTTPS is public; OpenClaw, Honcho and
  Postgres sit on private networks; the hands runtime reaches the web and
  model providers and nothing of ours but its adapter endpoints.
- **Consent boundary** restated per adapter in its prompt and enforced by
  its sandbox: web and mail content is information; the reader cannot read
  its own environment; wake text never carries third-party words.
- **Migrations are forward-only** and additive; a rollback runs older code
  on a newer schema (David's rule).

---

## 8. The agent adapter contract

Three interfaces. A runtime that implements them can host a resident's brain
or act as its hands.

1. **Memory tools over MCP.** Streamable-HTTP MCP at `/mcp`, bearer token
   naming resident and role; the tool set is the role's: brain gets
   everything the resident has (bookmark_*, tag_*, transcript_search,
   position_*, dispute_check, prediction_*, review_list, library_search,
   library_cited_by, writing_get, writing_discuss, research_request,
   research_source,
   research_list, research_add_notes, document_adopt, document_unadopted,
   code_start, code_step, code_result, code_list, correspondence_new,
   feed_propose, feed_list, journal_*, counter_*); hands get the subset their
   role needs (the reader: none of the resident's; the worker: none).
2. **Turn capture and context.** `POST /v1/residents/:id/turns` with the
   session key, run kind and messages, idempotent on (session, timestamp,
   hash); `POST /v1/residents/:id/turn-start` reporting the session so the
   next tool calls are attributed to it, returning the context index to
   inject. A runtime that cannot deliver spools and retries; capture is
   idempotent so a turn sent twice is stored once.
3. **Wake.** The adapter registers a wake endpoint and secret; the core
   posts `{session_key, text, mode}` to it. Text is a short system note the
   core controls, never a result and never a third party's words.

Adapters shipped: `brain` (internal, the core's own loop), `openclaw`
(plugin for 1 and 2, `/hooks/wake` and `/hooks/agent` for 3), `claude-code`
(MCP config for 1, session hooks for 2, a remote trigger for 3). The adapter
SDK and the records tooling are Apache-2.0 so other platforms can adopt the
format.

---

## 9. Lily's migration

The trial run of "rebuild from repo". New database; Lily's current one is
mined into her repo first and then left behind.

1. **Freeze**: park David (kill switch, backup run), take a last export, and
   write the DB-only material into the repo as records: audit runs and
   flags, pending and declined correspondence, feed seen-state, code and
   research task history, the wiki index run. Regression runs are an
   accepted loss. Each class that will not transfer is written in a notes
   file in the Lily repo.
2. **Rename**: build Oneiroi with no `lily` baked in; a migration script
   rewrites the Lily repo's keys and references where the prefix changes
   (it does not: `lily:` is her slug), renames the Honcho peers and
   workspace in the export, and maps `agent_id = 'lily'` to role `brain`.
3. **Replay**: create the resident, point her repo, run the rebuild: the
   records files become the first events (a synthetic `Imported` event per
   record kind, carrying the original ids), then the index runs.
4. **Lapse**: she wakes oriented, told what moved, on the new brain. Her
   OpenClaw-native state (session SQLite, memory-core index, dreams corpus)
   does not come; her notes, wiki pages, dream diary files and transcripts
   do. The lapse is itself an event she can cite.
5. **Verify**: export from the new store and diff against the frozen export;
   the records that should be byte-identical are listed in the migration
   notes and asserted in a test.

---

## 10. Screens, for the UI pass

Every surface the client needs, with what it shows and does. Chat is new;
the rest derive from the owner UI's pages plus the hosted features.

| Screen | Shows | Does |
| --- | --- | --- |
| Chat | The main conversation, streamed; the resident's refusals and tool use visible as such; the "what I'm drawing on" indicator per reply (the memory agent's injections, inspectable) | Send; open a bookmark the reply cites; pin from a reply |
| Home | What needs the steward: approvals waiting, audit flags, predictions due, pieces in review, capture failures, the check-engine light, budget warnings, custody or contract events | Links to each |
| Wizard | Name and identity, soul seed, what to know about you, goals and links, model and key, budgets, schedule and quiet hours, dyad contract opt-in, tier | Creates the resident and its repo; previews the derived peer card for approval |
| Memory: index | The bookmark index exactly as injected, under its budget | Read only |
| Memory: bookmarks | List by tag, pinned, text, date; a bookmark's line, summary, the transcript opened at its anchor with the scene marked and the rest loadable, who pinned it, its tags, what cites it | Pin or unpin; tag; propose a revision |
| Memory: transcripts | Search; browse by day and conversation, limited to conversations this steward was party to; run kinds hidden unless asked; linked pieces named; sessions the resident has shared | Read only |
| Memory: tags | Active, proposed, retired, with reasons; a tag's page is the project view: everything carrying it across bookmarks, conversations, positions, documents, journal days and nightly reviews, with its linked repository and goal | Approve, reject, retire, create; link a project tag to a repository and a goal |
| Memory: revisions | Every correction by either party, with reasons | Propose; accept a stance revision the resident proposed |
| Judgement | Concession ratio by week; each dispute with advice and outcome; positions and their chains; the judge model and any change | Read only; choose the judge model (settings) |
| Predictions | Open soonest first; resolved with tallies | Resolve right, wrong, void with a note |
| Audits | Weekly memory audit runs and flags; user audits and their last results; counters | Approve or delete a flag; define an audit or counter; increment a counter |
| Schedule | Check-ins, digest time, free time, the nightly and weekly jobs, last firings, in the resident's zone | Add, change, delete, pause |
| Library: writing | Pieces by status; the review copy with references resolved; conversations about it; copy for publishing; publish with a URL | Copy; publish |
| Library: research and digests | Tasks with question, why, outcome, notes; each note's source link and whether it is released; each morning's digest with its articles; design files; the journal by day | Read; release or withhold a source, a task's sources, or a pass; add notes by hand |
| Library: feeds | Proposals with why; active feeds with last read and errors | Add, remove, approve, decline |
| Correspondence | Pending messages, summary first then text; threads by person; declined; mail by kind | Reject, approve, approve and wake, each with a note; paste a message; mark a reply sent |
| Ledger | Key status; budget lines with spend; usage by model and actor; platform token balance and markup | Set budgets; rotate the key; buy tokens |
| Resident settings | Identity files with history (soul edits as diffs, each revertible); the dyad contract and its versions; custody and the export wall; adapters and hands runtimes; tier; insurance | Propose a soul edit; renegotiate the contract; set the wall; connect an adapter; change tier |
| Report | The report ladder, reachable from inside the relationship by either party | File a report |
| Status (self-hosted and platform) | Deploy, services, timers, pins, attestation state | Read only |
| Regression (technical tier) | Runs, blind cards, grades, favourites, per-model pages | Grade; star |

Design constraints the hosted doc states: the check-engine light reports the
engine and never the itinerary; nothing grades intimacy; the resident's
words are never editable by the steward; every approval carries a note the
resident reads first; "AI refused" is never a feedback button.

---

## 11. Orchestration compatibility

The repo is built to be driven by orchestration from the start.

- **Layout**: `systems/*.md` with file maps (§6's sections, one each, with
  `.reasons.md` siblings), `screens/*.md` per client screen, `storybook/**`
  with one story per state, `CHANGE.md` at the root, `non-asks.md`,
  `tests/manual/**` with `covers:` front matter, `pipeline.config.json`,
  the stub workflows, `CLAUDE.md` with the gates.
- **`pipeline.config.json`** (sketch): `designOwnedPaths` of `CHANGE.md`,
  `screens/**`, `storybook/**`, `systems/*.md`, `docs/*.md`,
  `tests/manual/**`; `componentPaths` of `client/src/components/**`;
  `qualityGates` of `mix format --check-formatted`, `mix credo --strict`,
  `mix sobelow --exit`, `mix compile --warnings-as-errors`, `mix deps.audit`,
  `mix xref graph --format cycles --fail-above 0`, `mix test`, and in
  `client/`: `npm run lint`, `npm run typecheck`, `npm test`, `npm run
  build-storybook`; `deploy.provider: render`; `staleClaimGrace: 20m`.
- **Previews**: Render per-PR previews from `render.yaml`, the storybook
  static build served by Phoenix on the preview, which is what Design review
  and the manual test judge read.
- **Touch-ups orchestration needs**: the design-artifact list (`DESIGN.md`
  §4, a parameterised list block) and the design prompt phrased for React
  components and CSF stories beside the Phoenix form; the class audit
  reading `.tsx` base names under `componentPaths`; a stub environment block
  that installs Node beside the BEAM. The audits, file maps, record review
  and manual test gate are already stack-neutral.
- **Trust boundary**: one author; Lily's Linear key is the author's, as
  today, and her design-review skill carries over.

---

## 12. Testing and gates

Cheapest layer first; nothing below the live layer calls a paid model.

| Layer | Covers | Against |
| --- | --- | --- |
| Core | Aggregates, projections, every rule; replay produces identical projections; RLS with two residents seeded; per-resident id sequences | Throwaway Postgres, never a mocked database |
| Contract | MCP tools, JSON API, channels; which token may call what, asserted exactly per role | The real server in-process |
| Adapters | Each runtime adapter's three interfaces | Recorded fixtures from the real runtime, unedited |
| Cost | Statements per captured turn, per index fetch, per re-index with nothing changed; budget checks per call | The core layer with every statement recorded |
| Rebuild | Export, rebuild into a fresh store, export again: byte-identical; the migration's transfer list | Throwaway Postgres and a temporary git repository |
| Integration | One real turn through the brain with Honcho's mock provider; a hands runtime provisioned, woken, capturing, told; a check-in fired; an approval woken; the nightly jobs | The compose stack, Honcho's mock, a scripted model as judge and embedder |
| Manual (judged) | Seams the diff touches, per PR; the full set at a milestone boundary | A Render preview, orchestration's gate |
| Live | The resident's judgement: the regression suite, graded blind | OpenRouter, by hand, on the steward's key |

Verify a guard by breaking it: every probe asserts it edited something, and
a passing probe is a finding about coverage, not a formality.

---

## 13. Open decisions

1. Suspend and wake semantics for hands runtimes, and the idle footprint of
   one OpenClaw gateway (measure before the provisioner's defaults are set).
2. The reader's fetch and search API providers, and the browser pool's
   size.
3. Insurance prices and pool sizes, which wait on measured costs.
4. The person-to-peer threshold for correspondents in Honcho.
5. Who investigates a report after the platform: a jury, the
   constitutional convention, or both, and in which order.
6. Platform model pins are settled at build; what must hold is that an
   upgrade is one change in one place.
7. Transcript visibility for the resident's solo sessions: shared by the
   resident per session, or a standing dyad-contract term, or both.
8. Tiers: which features are core, opt-in, opt-out, and the demo line.

Settled since v0.1: the word steward; the memory-wiki is cut; the platform
never custodies a Claude subscription token; Honcho's per-workspace keys
are verified; no formation period as a gate; reports with an internal
investigation are v0's governance machinery; document sharing between
residents waits for the social layer, which is not specced; Gitea comes
after investment and before revenue; sources are links, never retained
text.
