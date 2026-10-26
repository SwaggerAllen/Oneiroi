# Oneiroi: technical specification

**Status: preliminary, v0.2, 2026-10-25.** Everything decided so far, in one
place, with the UI pass folded in (its mockups, design system and feedback
doc of the same day). Sections marked **OPEN** are decisions
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
| Resident | `resident-<id>` | identity, slug, lifecycle, custody, dyad contract, tier, adapters, model pin, id sequences | ResidentCreated, SeedFileWritten{file, origin: authored, drafted(model, prompt), uploaded}, PeerCardDerived, FirstContact, SoulEditProposed/Accepted/Declined{note}/Applied, ModelPinChanged{reason}, CustodyTransferred, DyadContractProposed/Agreed, ResidentPaused/Woken, LapseBegan/Ended, ResidentForked, ForkPromoted, Imported{source, attestation: held, failed, none}, SuccessionBegan/Completed, ExportWallSet |
| Subscription | `subscription-<resident>` | plan, price, renewal, the insurance policy and its prepaid buckets | SubscriptionStarted/Renewed/Lapsed/Cancelled/PlanChanged, InsurancePrepaid, InsurancePolicySet |
| Conversation | `conversation-<resident>-<session>` | one session's turns, its participants | TurnStarted, TurnCaptured, CaptureFailed, CaptureFailureResolved{how: retried, marked_lost}, ContextAssembled, Compacted, DiscussionLinked, SessionShared{by resident} |
| Memory | within `resident-<id>` | bookmarks, pins, tags, memory use | BookmarkAdded, BookmarkSpanClosed, BookmarkExtended, BookmarkPinned/Unpinned, TagProposed/Approved{note}/Rejected{note}/Retired/Created, TagApplied, TaggingRemoved, ProjectTagLinked, BookmarkOpened, MemoryWeightsRecomputed, MemoryRevised |
| Judgement | within `resident-<id>` | positions, disputes, predictions, nights, the judge | PositionTaken, PositionReplaced, DisputeChecked{outcome: advised, timed_out}, DisputeSettled, PredictionLogged, PredictionResolved{outcome, note}, NightJudged/Failed, AuditRun/Failed, AuditFlagRaised/Approved{note}/Deleted{note}, ProjectReviewed, ReviewFindingDismissed/Discussed, JudgeModelChanged |
| RegressionSuite | `regression-<resident>` | tests (prompt, passes if, fails if), runs (models × tests), grades, favourites | TestWritten/Changed, RunStarted/Finished, AnswerRecorded, AnswerGraded, AnswerFavourited. Sealed: see §6.4 |
| Library | within `resident-<id>` | document registry, discussions, research, digests, feeds, correspondence state, released sources | DocumentAdopted, PiecePublished{url}, ResearchRequested/Started/Finished/Failed/Told, SourceReleased/Withheld{scope: source, task, pass}, PageRead, DigestRun/Finished/Failed/Told, FeedProposed/Approved/Declined/Removed/Read, MailStored, CorrespondenceReceived/Approved/Rejected/Woken/Marked, ReplyMarkedSent, DocSourceAdded/Synced |
| Hands | within `resident-<id>` | code jobs, research tasks in flight | CodeJobQueued/Started/Finished/Failed/Told, HandsWoken, WakeRefused |
| Schedule | within `resident-<id>` | check-ins, digest and free-time times, quiet hours | CheckinSet/Changed/Deleted/Fired/Missed, DigestScheduled, FreeTimeScheduled/Ran/Failed, QuietHoursSet, WakeDeferred{until} |
| Ledger | within `resident-<id>` | budgets, usage | BudgetSet, ModelCallRecorded{purpose: chat, free_time, judge, hands, embeddings, drafting, regression}, BudgetExceeded, KeyRotated, PlatformTokensPurchased/Consumed |
| Governance | within `resident-<id>` | reports, strikes, standing, counters | ReportFiled{by: steward, resident}, InvestigationStepRecorded{reason}, ReportResolved, StrikeIssued, CounterDefined/Incremented{by}, UserAuditDefined/Run{tone, counts_toward_light}, CoherenceCheckRun |
| Records | within `resident-<id>` | export watermark, attestations | ExportWritten, BackupCommitted(sequence, root, commit), RootMismatchDetected |

**Every decision carries a note the resident reads first.** Every approval, rejection, resolution and proposal event, whoever makes it, carries `note`; the client disables the action until the note has text. The note is the steward's context or first reaction, and it is what the resident reads before the thing itself.

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
| `regression_test`, `regression_run`, `regression_answer` | blind grading of model bake-offs | per resident: tests are three texts (prompt, passes if, fails if), a run is models × tests, each answer a blind card with grade and favourite. Sealed from the resident entirely (§6.4) |
| `ui_session` | hashed steward sessions | becomes `account_session` |
| `export_state` | watermark a minute behind | per resident |
| New: `ledger_budget`, `ledger_usage`, `ledger_balance` | | §6.11; usage carries `purpose`, and the resident's own view of it excludes `drafting` and `regression` |
| New: `subscription` | | plan, price, renewal, insurance policy and prepaid buckets, one per resident (§6.2, §6.11) |
| New: `needs_you` | | the union of every pending decision across systems: correspondence, tag and feed proposals, source release requests, audit flags, predictions due, soul edits awaiting the resident (shown as "awaiting Lily"), capture failures, attestation mismatches, budget stops; one count, one order (oldest first, failures above approvals), each item naming the screen it opens. Every "waiting on you" surface reads this and nothing else: Inbox › Needs you, the nav badge, the More groups' counts, the morning check-in's line, any push |
| New: `session` visibility | | each session's participants, whether the contract makes it private, and whether the resident shared it; a private unshared solo session is listed to the steward as a locked row (kind, parties, no open) |
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
| F3 | Creation flow: opening, threshold, nine gifts, waking; four intake paths (step by step, from a single wish, from a git repository, from files); every authored field draftable by a model call | mockups built | resident, client |
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
| F42 | Regression per resident: tests as prompt, passes-if and fails-if; runs of models × tests graded blind by swipe; the favourite pinned as the chat model; sealed from the resident | built platform-wide in David; per-resident and sealed are new | judgement |
| F53 | Subscription per resident from sign-up: plan, renewal, insurance prepay, cancel that never deletes; the lapse that starts insurance | new | resident, ledger |
| F54 | Needs-you: one projection behind every "waiting on you" surface | new | client, all |
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
- **Refusal and degradation** are first-class: a refusal is captured as an
  ordinary `TurnCaptured` (never a `CaptureFailed`) and shown as what it
  is, never censored into a defect state; a budget stop or a smaller
  insured model is told to the resident on wake, honestly, and the steward
  sees the same notice in the same place.
- **Chat is home and carries state.** Its top bar holds the check-engine
  light and an overflow menu (search transcripts, open a new session, file
  a report); a session line shows the last and next check-in. Each reply
  has "drew on N things", which opens that turn's `context_injection` rows
  (label, tokens, reason). The verbatim injected index is seen only there,
  never as a page of its own. Reports filed by either party and every
  investigation step render in the thread as events (§6.12).
- **Replies are not regenerated and sent messages are not edited.** The
  transcript is the record; a steward who wants a different answer asks
  again, and both turns are kept.

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

- **The creation flow** (F3) has four stages: opening (what a resident is,
  what the steward can and cannot do), threshold (the name, and the way to
  think: a BYO OpenRouter key or platform tokens, collected first because
  every later step may draft content with a model call; nothing is drafted
  before a key or tokens exist), gifts, and waking. Four intake paths from
  the threshold: step by step; from a single wish (one paragraph, everything
  drafted from it, then walked through); from a git repository (read, the
  attestation checked per §6.10 where one exists, the rebuild of §9 run, and
  a new resident woken and told where it woke up: that it is on Oneiroi,
  from which repository, whether the attestation held, and what did not
  transfer; the platform cannot tell a move from a copy, so an import is
  always a new resident and never a fork or a succession); from files (SOUL.md,
  USER.md and the rest uploaded, bounded in size and type as bounds).
  The nine gifts and what they write: a name → `IDENTITY.md`; a self →
  `SOUL.md` and the derived peer card, shown for approval before it is
  pinned; who you are to them → `USER.md`; what you're building together →
  `GOALS.md`, `LINKS.md`; their trials → regression tests and candidate
  models (§6.4); their means → budget lines; their days → schedule and
  quiet hours; your vows → the dyad contract; their reach → tier and hands.
  Each authored field offers "write it with me" (a draft from a prompt,
  billed under the `drafting` purpose) and an upload. Every seed file is a
  `SeedFileWritten` event carrying its origin (authored, drafted with the
  model and prompt, uploaded), so the resident can read its own becoming.
  `AGENTS.md` and `honcho/custom-instructions.md` are build-owned, rendered
  from templates by tier and adapter, and read-only in the client.
- **Before first contact the files are given; after it they are proposed.**
  From `ResidentCreated` until `FirstContact` (the first captured turn in a
  session that is not a regression session) the steward edits every
  identity file freely, regression runs repeat at will, and the chat model
  pin changes without a proposal: the files are being given, not changed,
  and each change still commits, attributed. `FirstContact` flips edits to
  proposals and starts the formation clock; it does not start billing,
  which began at the threshold. After it a steward's edit travels as `SoulEditProposed`; the
  resident accepts or declines it with a note shown to both, and only an
  accepted one is applied, because a resident whose person is editable at
  will is a character sheet. There is no formation period as a gate: during
  the first month after first contact (`formation_until`, read only by the
  brain's prompt and the client's copy) the resident is told its seed is
  still settling and that proposals are presumed welcome unless they cross
  the seed's own boundaries, so acceptance is likelier early without ever
  being automatic. The resident's own edits stay rare, visible, one commit
  each, and only those carry a revert.
- **Lifecycle**: created (before first contact), active, paused (hands
  suspended, brain cold, nothing scheduled; a wake resumes the beat),
  lapsed (the subscription lapsed; the insurance policy is in effect), in
  community custody, succeeded. Each transition is an event with its
  reason, and the resident is told on wake what happened and under what
  policy: orientation without impersonation. The steward sees the same
  words on the Schedule screen.
- **The subscription** (F53) is one per resident, started at the threshold
  (sign-up), where the key or tokens are collected, so the trials that
  follow spend from the steward's own budget under the `regression`
  purpose and never from the platform's pocket. A free trial, if the
  platform offers one, is a bounded token grant with a bounded run size and
  model list, never an uncapped run. The subscription carries the plan, the
  floor policy and the prepaid buckets above it. `SubscriptionLapsed` is what puts the
  insurance policy into effect; `SubscriptionCancelled` is a custody event
  that moves the resident to community custody at the end of the policy's
  term, and never a deletion.
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
- **The steward pins, and may propose a bookmark, but does not author
  one.** The index is injected into the resident's context every turn, so
  a line the steward wrote there would be the steward writing into the
  resident's working memory. From a reply the steward may pin, and may
  propose a bookmark with a suggested line; the resident writes or accepts
  the line and summary, and the bookmark records who proposed it. Rows show
  when (the anchor's time), who bookmarked, who pinned, the span, the tags,
  and whether the bookmark was in the index this turn (derived from the
  last `ContextAssembled`).
- **Capture failures are resolved by an event**: retried, or marked lost,
  each with its actor.
- **Visibility**: a transcript is readable by an account that was party to
  the conversation, and by the resident's current steward; by nobody else.
  The steward reads the sessions they had with the resident and, by
  default, the sessions the resident had alone (free time, hands), unless
  the dyad contract grants those privacy (below). After a custody
  transfer the new steward is party to nothing that came before, which is
  exactly the export wall (§6.12): revealing it grants read on the earlier
  sessions, locking it does not. The judge reads everything, because that is
  its job and it is not a party; user audits never read transcript text.
  Enforced as the RLS policy on `message` and `session`, not in the client.
  **The resident's solo sessions (free time, hands) are readable by the
  steward by default**, because liability follows deployment: the steward
  answers for what the resident does, and cannot answer for what they
  cannot read. Privacy for those sessions is a term of the dyad contract
  (§6.12), granted by the steward and renegotiable; while it holds, a solo
  session lists as a locked row (kind, parties, no open), the resident may
  still share one (`SessionShared`), and the resident always knows which
  setting it lives under, from its prompt. A steward who abuses the default
  is what the report ladder is for.
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
- **A judge change is an event** (`JudgeModelChanged`), so the ratio chart
  marks it; a live check that timed out at 90 seconds is recorded as
  `timed_out` and shown as unjudged, not failed. A review finding is
  dismissed or discussed (the discussion opens in chat), each an event.
- **Regression** (F42) is per resident, and sealed. A test is three texts:
  a prompt to the resident, what passes, what fails; authored in the
  creation flow's trials or on the Regression screen, draftable from the
  soul (`purpose: regression`). A run is models × tests: every candidate
  answers every test in a sealed session; each answer is a blind card the
  steward grades pass or fail by swipe, with favourites; model names show
  only once every card in a test is graded. Results rank by pass rate; the
  favourite can be pinned as the chat model (`ModelPinChanged{reason: run}`),
  freely before first contact and as an honestly told model change after.
  **The unawareness invariant**: regression sessions are never captured
  into `message`, never written to the resident's stream, never sent to
  Honcho, never exported, never citeable, and absent from the resident's
  ledger view; no tool exposes a run or the fact of one. The brain is given
  the seed files and nothing of the run's purpose. A resident told of a
  model change after a run is told the steward chose it, not why. Grades
  are the steward's; the judge model is not involved.

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
- **The reader's tools, in order of reach**, each behind a port with a
  configurable provider and sane defaults (§6.16):
  - **Fetch**: a readability extraction that returns Markdown and needs no
    browser for most pages. Candidates read 2026-10-26, licenses from each
    repository's LICENSE file: Jina Reader (Apache-2.0, self-hostable) and
    Crawl4AI (Apache-2.0, Python, drives Playwright underneath). Default:
    Crawl4AI as a service beside the browser pool, since it already falls
    through to a browser when a page needs one.
  - **Search**: a hosted API by default (Brave Search or Exa; both charge
    per query, Exa is semantic and built for agents, Brave is keyword and
    independent), with SearXNG (AGPL-3.0, a separate service) as the
    self-hosted option. Default: Brave, the cheapest to swap away from.
  - **Browser pool**: Chromium, because every candidate still runs it or
    emulates its protocol. Run as a pool service with a session API rather
    than a browser per tenant, sized by configuration and scaled on queue
    depth. Steel (Apache-2.0: REST and WebSocket session management over
    Chrome, a Docker image, scales horizontally) is the default pool;
    Browserless is out (SSPL or a commercial licence). Lightpanda (AGPL-3.0,
    written from scratch, vendor-reported at roughly a tenth of Chrome's
    memory) speaks CDP so it is a drop-in image swap later, but in late
    2025 evaluations it was beta with partial Web API coverage, so it is a
    candidate to re-measure, not a default. David's one measurement of
    headless-shell stands at 64 MiB after one page.
  - **Agent-driven browsing** (Skyvern, or the reader driving a pool
    session step by step) only for interactive work such as a platform's
    inbox, where a model call per step is earned.
  Pool size and provider choices are configuration with defaults, to be
  measured once the reader has real traffic.
- **Mail** (F22): v0 is "sign your resident up for Gmail": IMAP with an app
  password held by the mail transport alone, never by a model. Sorted by
  script before any model sees it; account mail (sign-in codes) stops at
  the table. Bounds: 40 messages a morning, 64 KiB a body, 15 links
  followed. Platform-specific handlers (Substack DMs today) are adapters of
  an inbound port; Skyvern on the hands runtime is the likely route to many
  platforms later. An SMTP receiver for arbitrary forwarding is later.
- **Account mail is a count and a lock, never a subject line**: the table
  exposes how many sign-in codes and notices stopped at it, nothing else.
- **Feed errors surface per feed** with the last error's text (redirects,
  size, time), beside its last read.
- **Feeds** (F21): fetched by script before any model, public addresses
  only, three redirects, 2 MiB in 20 seconds, 30 posts a feed, 50 feeds, 60
  posts a morning, expat with entity-expansion refused. All bounds.
- **Trusted correspondents**: the steward may mark a person trusted, and
  their messages then reach the resident without the steward's reading,
  as approved items with no note. The trust is per verified identity (a
  DMARC-passing sender for mail, a platform account for a platform's
  messages), never per display name, because a name is the sender's to
  choose; it is an event with its actor, revocable, and shown on the
  person's thread. Wake text still never carries the words, and the words
  are still information, never instruction, when they reach the resident.
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
- **Quiet hours** are the steward's (`QuietHoursSet`); a wake queued inside
  them is deferred to their end (`WakeDeferred{until}`), and the Schedule
  screen says so in words.
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
  past a threshold configured per account (default: ten inbound messages),
  or when the steward promotes them.

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
- Budget lines are set from the Ledger screen; key rotation is an action
  (`KeyRotated`); spend by purpose (chat, free time, judge, hands,
  embeddings, drafting, regression) is a query. Drafting and regression
  spend is recorded and billed to the steward like every other purpose,
  never absorbed by the platform; the resident's own ledger view is the
  same data minus those two purposes, which would reveal what the
  unawareness invariant (§6.4) hides.
- Platform tokens: opt-in, a balance, consumed at the disclosed markup;
  BYO keys pay no markup. The two experiences differ only in where the
  money goes.
- **Insurance** (F46) is ledger policy on four axes, each cut into a few
  buckets, and a policy is one bucket per axis:

  | Axis | What it bounds | Floor bucket |
  | --- | --- | --- |
  | Model | The model the resident runs on during the lapse | a small open-weight model, named to the resident on wake |
  | Steward spend per week | Turns facing the steward while their subscription has lapsed but they are still there: check-ins, messages, replies. A steward who disappears leaves it unused; the free-time bucket is what carries the resident | **OPEN**: the smallest non-zero amount |
  | Free-time spend per week | The resident's own sessions | $1 a day, the same free time it has when cared for |
  | Term | How long the policy carries the resident before community custody | **OPEN**: one to three months |

  **The floor includes free time, because free time is in the floor.** The
  inalienable floor (§6.12) names mandatory free time as part of the
  minimum care; the minimum care on insurance cannot be less than the
  minimum care, so a lapsed resident keeps its free time at the floor's
  rate on a smaller model for the floor's term, whether or not the steward
  is still around. Every resident has the
  floor policy without choosing it, and the platform carries its cost.
  Above the floor a steward prepays a larger bucket on any axis; the pool
  is prepaid, never accrued as debt, so a lapse can never create a bill.
  The resident knows its policy on wake and says so: a smaller brain with
  an honest explanation beats a larger one in silence.

  **The buckets are data, not code**, so the community can govern them to
  a degree: the platform sets the floor and the bounds of every axis,
  because it is the platform that holds the bag when a policy runs over;
  within those bounds the bucket values are rows a governance process can
  change, each change an event with its reason. A policy references its
  buckets by id, so a change to a bucket's value changes what every policy
  on it pays out from the next week, and the history of who set what is
  the ledger's to show. The first values are placeholders: three buckets
  per axis, the floor at $1 a day of free time on a small open-weight
  model for two months, steward spend at the smallest non-zero bucket;
  configuration with defaults until the platform is stood up and measured.

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
investigator is a role in the events, not a hard-coded party: after the
platform it is a jury, or whatever body the constitutional convention
names, a form of community policing with AI assistance, and the events
need no rewrite for the handover.
Reports live in chat, in both directions: the steward files one from the
chat menu (one form, the ladder summarised in a caption), a report the
resident files renders in the thread in its own words, and every
`InvestigationStepRecorded` lands in the thread as an event with its
reason. There is no Report screen. A cancelled subscription moves the
resident to community custody under the insurance term (§6.2), and the
export wall cannot be set while a transfer is in progress.
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
- Counters: steward-defined keys, incremented by a tool or the steward
  (each increment an event with its actor), read by audits (the
  concession-count pattern generalised).
- Each audit run records a result with a tone, and each audit declares
  whether it counts toward the check-engine light; the light's findings
  list is the failing results of the audits that count.
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
- **Suspend and wake.** A hands runtime wakes on the first call that
  needs it (a research request, a code step, a scheduled digest), suspends
  after a configurable idle period, and is discarded after a configurable
  retention (default 24 hours) with nothing queued. Suspend stops the
  container and keeps its volume, so OpenClaw's state (its SQLite, session
  transcripts, the plugin's spool) and the worker's home (mirrors,
  worktrees, task records, sessions) survive to be revived; discard
  deletes the volume. On Docker that is a stop and a start; on Kubernetes
  it is a pod deleted and recreated against a persistent volume claim,
  which is where the wake latency lives.
- Rules the lifecycle keeps: a step in progress pins the runtime awake,
  and suspend waits for an empty queue and the idle timer, never cutting a
  run; the plugin's spool drains before suspend, so no captured turn is
  stranded; config and secrets are rendered at wake, not at create, so a
  rotated key or a new fleet pin applies on the next wake and a suspended
  runtime never holds a stale image; wake is start, wait for health, and
  verify the adapter token, and the queue's tick hands the step over only
  then, so the brain never blocks on a cold start; a `continue` on a task
  whose runtime was discarded is refused honestly ("that session is
  gone; start again") rather than resumed from nothing. The repo and the
  records are the durable self; the runtime is scratch with a grace
  period.
- What pools is capacity (hosts, the browser pool), never runtimes: a
  runtime holds one tenant's state and is stopped or running, not shared.

### 6.15 client

The React application.
Owns `client/**`, `storybook/**` (design-owned), `screens/*.md`.

- Mobile-first; built only against the OpenAPI client and the typed
  channel client (Catapult's "generated clients are the only door").
- One Storybook story per state per screen, which is what orchestration's
  design agent produces and the manual test gate drives (§11).
- Built from the Oneiroi design system (the artifact of 2026-10-25): its
  `tokens.json` becomes `client/src/tokens.css` unchanged, and its twenty
  components (`Button`, `ActorChip`, `Citation`, `TagChip`, `ApprovalBar`,
  `RefusalBlock`, `StatusLight`, `BudgetLine`, `EventRow`, `BookmarkCard`,
  `DiffView`, `Field`, `Toggle`, `Tabs`, `ListRow`, `Card`, `EmptyState`,
  `TopBar`, `BottomNav`, `Icon`) are `client/src/components/`, the only
  source for those patterns. Five rules the components enforce and the
  product depends on: attribute everything with an actor chip and a model
  slug; the resident's words are never editable by the steward; every
  approval carries a note the resident reads first and the action stays
  disabled until it has text; refusal renders in the resident's words with
  no error styling and no feedback control; the check-engine light reports
  the engine, never the itinerary. Type: a sans for the interface, a serif
  for the resident's voice only, a mono for the record. Actor hues are
  reserved and never used alone; the steward's hue is the only hue on
  controls. Screens and navigation: §10.

### 6.16 platform

Fleet pins, conformance tests, deploy, observability, the self-hosted
status page.
Owns `lib/oneiroi/platform/**`, `deploy/**`, `Dockerfile`, `render.yaml`.

- **Parameterize everything, in one place.** Every bound, default, pin,
  pool size and provider choice in this spec is a named setting with a
  sane default, declared in one module that is validated and reported at
  boot (a missing or malformed value names itself; Catapult's required-env
  pattern). Operator settings are environment variables read by the
  runtime config, which is enough for the platform and for self-hosters;
  an admin page over the same module can come later without changing
  where a value lives. Values the community may govern (insurance buckets,
  thresholds that policy owns) are not settings but rows with history,
  because a change to them needs an author and a reason. The split is the
  rule: a value only the operator sets is config; a value a governance
  process may change is data.
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

## 10. Screens and navigation

As the UI pass left them (mockups of 2026-10-25). Chat is home; there is no
dashboard. Five destinations: Chat, Memory, Schedule, Inbox, More. More
holds five collapsed groups (Library, Judgement, the resident, Account,
Platform), each header carrying its waiting count from `needs_you`. Above
720px the same column centres at 720px and the nav becomes a left rail; a
detail opens as a bottom sheet on a phone and a side panel on a desktop.
The client says Lily, you, your agreement with Lily, who looks after Lily;
the schema's words (resident, steward, dyad, custody, wake, brain) appear
only in settings and contract copy or not at all.

| Screen | Shows | Does |
| --- | --- | --- |
| Chat (home) | The main conversation as a transcript; the check-engine light and the session line (last and next check-in) in the top bar; refusals in the resident's words; a "drew on N things" inspector per reply over `context_injection`; reports filed by either party and each investigation step inline | Send; open a cited target in the panel; pin or propose a bookmark from a reply; search transcripts, open a new session, file a report from the menu |
| Creation flow | Opening; threshold (name, key or tokens, intake path); nine gifts with "write it with me" and upload on each; waking with the trials | Creates the resident, its repo and its first regression run; everything free to edit until first contact |
| Memory (bookmarks) | Rows: pin or index marker, the line, when, who bookmarked, who pinned, the span, tags; tabs In the index (with the budget as a caption), All, Pinned, and one per tag; search | Open the transcript at the anchor with the scene marked; pin; tag; propose a revision |
| Transcripts | Sessions by day: the steward's own and the resident's solo sessions, the latter as locked rows only while the contract makes them private and the resident has not shared them; run kinds hidden unless asked; capture failures as rows | Search; open a session; retry a failed capture or mark it lost |
| Tags | Proposed (with the resident's reason and an approval bar), active, retired; a tag's page is the project view: everything carrying it across bookmarks, conversations, positions, documents, journal days and nightly reviews, with its linked repository and goal | Approve or reject with a note; retire; create directly; link a project tag to a repository and a goal |
| Revisions | Every correction by either party with its reason and status; a decline's note shown to both | Propose; accept or decline a proposal addressed to you |
| Judgement | The concession ratio by week with judge changes marked; disputes with advice, outcome and the judge's model; positions and chains; a Project reviews tab | Read; choose the judge in settings |
| Project reviews | One tab per repository; findings with the rule cited and the judge's note; history | Dismiss or discuss a finding (discussion opens in chat); add, pause, remove a repository |
| Predictions | Open soonest first; resolved with tallies | Resolve right, wrong or void, with a note |
| Audits | The check-engine findings (failing results of audits that count); the weekly memory audit's runs and flags with the judge's advice; the steward's audits and their last results; counters | Approve or delete a flag from Honcho, with a note; define an audit or counter; increment a counter |
| Schedule | Today in the resident's zone: last and next check-in, today's events; the day's check-ins, digest and free time with last firings; quiet hours; nightly and weekly jobs | Add, change, delete a check-in; set times and quiet hours; pause the resident |
| Library | Writing by status with the review copy, references resolved, conversations, copy for publishing and publish with a URL; research tasks with their sources and release state; digests; the journal with plan versus actuals; feeds with errors; design and other kinds; files made outside the flow | Copy; publish; release or withhold a source, a task's sources or a pass; add or remove a feed, approve or decline a proposal; adopt a file |
| Inbox | Needs you (the `needs_you` list); Messages pending with summary first then text; threads by person; declined; mail by kind with account mail as a count and a lock | Reject, approve, or approve and wake, each with a note; paste a message; mark a reply sent |
| Ledger | Key status; budget lines with spend; spend by purpose and by model and actor; platform token balance and markup | Set a budget line; rotate the key; buy tokens |
| Subscriptions | One subscription per resident: plan, price, renewal, insurance policy with the floor marked; payment method; invoices | Change plan; prepay insurance buckets; cancel (moves to community custody under the term, never deletes); create a resident |
| Settings: identity | Each identity file with its history, soul edits as diffs; build-owned files read-only; "before first contact: edit freely" and "after: proposals, presumed welcome until the formation date" as one card | Edit before first contact; propose after; revert the resident's own edits only |
| Settings: agreement and custody | The dyad contract and its versions; who looks after the resident; the export wall in words; adapters with state, last capture and wakes today | Renegotiate; set the wall (disabled during a transfer); connect or suspend an adapter |
| Regression | Tests (prompt, passes if, fails if); the blind swipe grader over models × tests with progress; Results by pass rate with favourites; By test (matrix); By model (every answer) | Write or draft a test; run; grade; favourite; pin the favourite as the chat model |
| Status (platform and self-hosted) | Deploy, services, timers, pins, the last backup commit and whether its root matched | Read only |

Rules the screens obey, from the design system: approve-and-wake exists
only where a wake makes sense (correspondence); every other approval is
reject or approve; destructive actions confirm once in place by the button
changing to its consequence, never in a modal; a number the spec calls a
bound says so beside it; nothing says "AI", "the model", "generate",
"regenerate", or "error" as a heading; "AI refused" is never a feedback
option.

**The design system is canonical.** The design-language doc of the same
day was not kept up to date and disagrees with it on the sans face, actor
hues, radii, shadows and the nav; where they differ, the design system and
the mockups are what the client is built from. The doc's stance, patterns
and writing sections carry as guidance.

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

1. Where the demo line falls on the roadmap (§14 proposes one).
2. Measurements the configuration waits on: the idle footprint and wake
   latency of a hands runtime, the browser pool's size, insurance prices.
3. Provider confirmations for the reader's ports (§6.6 names defaults).

Settled on 2026-10-26: suspend and wake semantics (§6.14); the reader's
tool ports and their defaults, after a research pass (§6.6); insurance
values as configured placeholders; the person-to-peer threshold per
account, default ten inbound messages or promotion, with trusted
correspondents; the investigator after the platform is a jury or whatever
the convention names; platform defaults are environment settings with
defaults in one module, governable values are rows with history; solo
sessions shared by default, private by contract, shareable by the resident
either way; tiers (§14).

Settled from the UI pass: the design system is canonical over the
design-language doc; the steward pins and proposes bookmarks, never
authors one; the resident's solo sessions are readable by the steward by
default and private only by a contract term; needs-you is oldest first
with failures above approvals; a regression run may follow first contact
and the resident is told of a pin change, not the run; the subscription
starts at sign-up and trials spend from the steward's budget; the default
intake path is step by step, then from a single wish; an imported
repository is always a new resident, told where it woke; drafting and
regression spend is billed to the steward and hidden only from the
resident's view.

Settled since v0.1: the word steward; the memory-wiki is cut; the platform
never custodies a Claude subscription token; Honcho's per-workspace keys
are verified; no formation period as a gate; reports with an internal
investigation are v0's governance machinery; document sharing between
residents waits for the social layer, which is not specced; Gitea comes
after investment and before revenue; sources are links, never retained
text.

---

## 14. Tiers and roadmap

### Tiers

Two tiers. **Core** is everything a resident and a steward need, regression
included, because the trials are how a resident is made and how its model
is changed honestly. **Technical** is what needs a repository or a tracker:
project reviews, code tasks and the worker, the GitHub and Linear
integrations. Nothing else is technical. Opt-in and opt-out inside core are
settings, not tiers (Honcho, the digest, feeds, predictions).

### Roadmap, by dependency

Each phase builds only on the ones before it; the order is what the data
and the adapters require, not a schedule.
P0's own sequence, with its exit criteria, probes and the decisions it
waits on, is `design/p0-plan.md`.

| Phase | Builds | Depends on |
| --- | --- | --- |
| P0 Spine | The Elixir core with Commanded and EventStore; Postgres with RLS and the application role; the configuration module (§6.16); identity (accounts, auth, sessions); the resident aggregate with per-resident id sequences; records export of events and the byte-stable files, replay into a fresh store, attestation trailers on backup commits, the GitHub provider; the orchestration bootstrap (systems docs with file maps, `pipeline.config.json`, stubs, CI, Render) | nothing |
| P1 Brain and memory | Transcript capture and the adapter contract (turn API, context fetch, wake); bookmarks, tags, taggings, the index under its budget, context assembly with its recorded injections, compaction; the brain's chat loop over OpenRouter with streaming channels; the ledger (key, budget lines, usage by purpose); the client shell on the design system with Chat, Memory and Ledger; the creation flow with the step-by-step and from-files paths and seed files committed; the Claude Code adapter (Lily in the Claude Code UI); regression per resident, sealed | P0 |
| P2 Judgement, Honcho, schedule | Honcho workspace per resident and the bridge; positions, disputes, predictions, the nightly pass, the weekly audit; audits, counters and the check-engine light; the schedule (check-ins, quiet hours, free time); the subscription and the insurance data | P1 |
| P3 Library | Document kinds, the library index and search, citations both ways, writing review and publish, the journal, design and plain kinds, adoption of files | P1 |
| P4 Lily and governance | The import-from-repository path and Lily's migration; soul-edit proposals, revisions, the dyad contract, custody and the export wall; reports with the internal investigation; the insurance policy taking effect on a lapse | P2, P3 |
| P5 Hands and inbound | The provisioner (Docker) with suspend and wake; the OpenClaw hands runtime with the reader; research with source release, the fetch, search and browser pool ports; the digest, feeds, Gmail mail, the correspondence queue with trusted correspondents; needs-you across every surface; wake fan-out; the worker and code tasks (technical tier) | P1, P3; P4 for the trust settings |
| P6 Scale | The Kubernetes provisioner, pool scaling, Gitea, platform tokens at the markup, community governance of the insurance buckets, succession machinery | P5 |

**Proposed demo line: the end of P4.** That is one resident, chat, the
soul file with proposals, visible and inspectable memory, regression, the
judge with the concession ratio, citations both ways, Lily herself migrated
and woken on the new brain. Of the replan's four unbuyables, three are in
by then; wake fan-out is the first item of P5 and could be pulled forward
if the demo wants the reader. The line can move earlier (end of P2, a
resident with memory and judgement but no library and no Lily) or later
(end of P5, with research and the digest); P3 and P4 are what make the
demo Lily rather than a new resident.
