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
  David recomputed a countdown daily and left stale numbers in every
  file that had copied one. The date is the record; the
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


## Round 12: going public (2026-10-27)

An audit of the tree and its history before the repository was made
public, with the design as the thing to get feedback on. Nothing secret
and nothing personal turned up; what follows is what changed.

- The README orients a stranger: a work in progress, the design ahead
  of the code; the four things the design names from outside the
  repository (Lily, David, Catapult, orchestration) get a footnote
  each and no more, and `design/names.md` is pointed at as the bridge
  between the spec's function words and the `systems/` names.
- Every quotation names its translator (the three Edda lines were
  Bellows, uncredited), and `LICENSING.md` says the quotations are
  reproduced as quotation with attribution and are not licensed under
  either licence. The Kulea quotation stays pending: the word itself
  may yet change.
- The ids that identify the author's accounts leave the tree:
  `pipeline.config.json` names the metronome Worker's URL and the
  Linear team, project and actor ids, and then the Render service id,
  as `${…}` references, read from the repository's Actions secrets
  (orchestration's DESIGN §5): secrets rather than variables, though
  none is a credential, because a public repository's run logs print
  each step's environment and mask only secrets. The twelve stubs and
  `ci.yml` hand them over. The orchestration change merges first.
- The one cautionary example that named a date in the author's life
  now names a countdown.
- The commit trailers naming the model and the session stay: they are
  the record of how the thing was made.
- The last function words in prose and comments (the platform system,
  the substrate) become Apsu and Daedalus, except in the spec, which
  keeps its function words by `design/names.md`'s rule, and in the
  glosses, where the function word is the point.

## Round 13: the ledger's stream, and development from the thread (2026-10-29)

- Orchestration is set up and verified (SETUP §5's ticket reached Done
  unattended), and the author chose to develop P1 through P4 directly
  from a session rather than through tickets, at full throttle; the
  tracker is ignored for that stretch. The gates, the probes and the
  one-PR-at-a-time rule stay.
- The ledger has its own stream, `ledger-<resident_id>`, where spec
  §3.1 drew it within `resident-<id>` (systems/nisaba.md #9): Commanded
  holds one aggregate per stream, the ledger writes at the resident's
  turn volume, and P0's `mint_id` was built so another system could
  take an id and write its own stream. The records export still reads
  the resident stream only; whether and how spend is exported is the
  author's to decide, with the two hidden purposes in mind.
- Money is nano-dollars as integers (#10); a missing budget line is no
  limit (#11); a cost the provider did not report is a marked zero
  (#13). Req joins the blessed list as the port's HTTP client.
- The steward's OpenRouter key is identity's, on the account
  (systems/gaia.md #11), and the ledger reads it wrapped.
- Production answered as `http://localhost:8080` until the endpoint's
  `url:` came from `RENDER_EXTERNAL_URL` (systems/apsu.md #19).
- The brain is a system of its own, `Oneiroi.Brain`, function-named
  until the author names it (systems/brain.md): memory depends on the
  resident system for ids, so the loop that depends on memory cannot
  live in the resident system without a cycle. The socket takes a token
  rather than the cookie (systems/brain.md #6).
- Memory's bookmarks, tags and taggings have their own stream,
  `memory-<resident_id>`, with the bookmark number minted by the
  resident aggregate (systems/kumbukumbu.md #19): the same reasoning as
  the ledger's, and the same open question about the export, now
  covering the store a resident would most want in its repository. The
  index is pins first and at most half the budget, saying what it left
  out (#20); the words are the resident's and the tag set the steward's,
  held by the actor's kind at the command edge (#21); compaction is a
  summary on the session with a watermark, deleting nothing (#23). The
  brain's tools are the memory functions built so far, every call
  captured as a `tool` message (systems/brain.md #10), and compaction
  opens the turn that finds the session over the line, flush first
  (#11).
- The identity files are events with their origin on the resident
  stream, written whole (systems/agathos-daimon.md #11); first contact
  is recorded by the brain's turn and taken once, and flips a steward's
  write to a proposal the resident decides with a note (#12);
  `AGENTS.md` is rendered from a template, never stored (#13); the files
  ride in the export and the soul class (#14). Drafting lives in the
  brain because of the dependency direction (systems/brain.md #14).
  Behaviours (Ethos) are rows the resident owns with a closed trigger
  set and two scores computed on read (systems/kumbukumbu.md #24);
  retrieval is memory's, injected as "how I act", and choice is the
  brain's (#25).
- Regression is built under `Oneiroi.Eunomia` (the system's name, not
  the spec's `regression/`): its own stream with its own test counter,
  nothing exported, the sealed session the brain's seed context, cards
  blind until a test is graded, and one test holding the unawareness
  invariant over every resident-reachable surface (systems/eunomia.md
  #9 to #12). The pin is the resident's, told once after first contact
  (agathos-daimon #15, brain #15). Adapters are registrations with a
  role and a token shown once, and an adapter's token opens four paths
  and nothing else (agathos-daimon #16); the MCP server at `/mcp`
  serves the brain's tool table. Two measured defects landed with the
  adapter test: a second-precision wire instant crashed a projector and
  took the handler tree down (kumbukumbu #26), and a role converted
  with `String.to_existing_atom` raised in a process that had not
  loaded the code naming it; both are closed lists now.

## Round 14: the schedule (2026-10-29)

- The schedule is built under `Oneiroi.Sunna` (the system's name, not
  the spec's `schedule/`): its own stream per resident, a firing as an
  event before the wake, a day's outcome one of fired, missed or
  deferred, and a check-in set or changed after its time today waiting
  for tomorrow (systems/sunna.md #13). Times of day are the resident's,
  in a zone on the resident's row that Agathos Daimon owns and the `tz`
  database resolves (sunna #10, agathos-daimon #17). `tz` (Apache-2.0)
  is the one new direct dependency, taken because Erlang ships no zone
  data and a check-in at 06:00 is nothing without it.
- The wake is a port, `Oneiroi.Sunna.Wake`, with the brain named in
  `SUNNA_WAKE`: the brain reads the schedule's dates on every turn and
  the schedule wakes the brain, and a call each way is the cycle both
  gates reject (sunna #12, brain #17). Free time is a session of its own
  kind under its own purpose, once a day, a failure said (sunna #14).
  Dates are rows and the brain is shown their countdowns as a section
  derived on the read (sunna #15).
- Two defects the tests found before the gates ran, recorded beside the
  code: a deferred wake never fired at the end of quiet hours (the
  aggregate answered every recorded outcome with no event), and the
  tick's roster read under the worker's process scope alone would have
  answered no rows on the live policy (sunna #11).

## Round 15: judgement (2026-10-29)

- Judgement proper is built under `Oneiroi.Eunomia` on its own stream,
  exported and citeable where the regression suite beside it stays
  sealed (systems/eunomia.md #14): positions in chains that cannot fork
  (#15), the live check with the judge's advice or a timeout recorded
  as unjudged (#16), settlements with a note and the concession ratio
  by week counting earned concessions (#17), the nightly pass within
  David's bounds with a quiet day calling no model and a reply citing a
  message it was not shown failing the night (#18), the nightly job
  under the platform scope by name (#19), the judge chosen by the
  steward and never the resident's chat model, pinned or defaulted
  (#20), predictions the steward alone resolves (#21). Trials derived
  from behaviours ride in a regression run beside the authored tests
  (#8, #11).
- The brain depends on judgement for the resident's tools, so the
  sealed session's context moved out of the brain: Eunomia builds it
  from the brain's prompt file and a new resident-system export, the
  identity context, which the brain's own turn now reads too
  (brain #16, agathos-daimon #18).
- Two defects the tests found before the gates ran: a second nightly
  run for a judged day paid for a verdict the aggregate then discarded
  (eunomia #18), and an unpinned resident's judge could be set to the
  model it chats on, because only the pin was compared (eunomia #20).
- Open for the author, carried: the judge's calls bill to the
  resident's ledger under `judge` (critique 17 asked to whom); the
  platform's judge slug is a placeholder until a dated one is pinned.

## Round 16: the Honcho bridge and the weekly audits (2026-10-29)

- The bridge is built under `Oneiroi.Proteus` on its own stream,
  everything through a port with Honcho's HTTP API behind it and an
  in-memory Honcho in the suite (systems/proteus.md #8). The HTTP
  bodies are claims until the pinned image answers them (#9) and the
  table reads wait on that image (#10). Provisioning is the first
  captured turn's, with the two peers and the rendered instructions
  (#12); a turn syncs once as the two peers' words and a failure is
  the bridge's, never the turn's (#13); the card is the soul's
  paragraphs, set from git on provision, after a soul commit and by
  the weekly audit when a dream moved it (#14, sima-qian #13);
  Honcho's context is a bounded section of the brain's turn (#15,
  brain #19). The custom instructions are the resident system's second
  rendered template (agathos-daimon #19).
- The weekly memory audit is judgement's through the bridge (eunomia
  #22): the judge over Honcho's conclusions against positions and the
  soul, flags the steward approves (the conclusion leaves Honcho) or
  deletes, each with a note; Sunday, after the card audit.
- One defect the tests found before the gates ran: a retried turn was
  sent to Honcho twice and recorded once, because the aggregate's
  once-a-turn answer came after the send (proteus #13), the night's
  lesson at a second port.
- Open for the author, carried: a person's own peer past the threshold
  and the steward's promotion wait on inbound; `PROTEUS_HONCHO_URL`
  and `PROTEUS_HONCHO_ADMIN_KEY` are unset until a Honcho is deployed
  beside the instance, and the port fails with them unset.

## Round 17: audits, figures and the light (2026-10-29)

- Audits are built under `Oneiroi.HuginnMuninn` on their own stream
  (systems/huginn-muninn.md #9 to #13): a counter is a key the steward
  names and a value nobody writes, incremented by either party with the
  actor on the event; a countdown is a figure read from the schedule,
  never a row here; a steward's audit is a rule over a figure with a
  tone and whether it counts; the built-in checklist reads rows (the
  attestation, open capture failures, failed syncs, missed check-ins,
  overdue predictions); every run is an event with a tone and the
  check-engine light is the failing results of the audits that count,
  read from each audit's latest run. The brain reads the figures as a
  section and increments through a tool (brain #20); `figure` joins
  the tagging kinds (kumbukumbu #27); the schedule's firings and the
  resident row's attestation word are reads for it (sunna #17,
  agathos-daimon #20).
- Citation drift and the journal's delta, the spec's first two built-in
  audits, wait on the library and the journal (P3); the composite
  coherence score waits on a decision for it to feed.

## Round 18: the subscription and the insurance floor (2026-10-29)

- The subscription is built in the ledger on its own stream
  (systems/nisaba.md #15): started once with the floor policy, renewed
  by record rather than charge until a payment provider lands, its
  plan changed, lapsed, cancelled with a note. Nanshe's buckets are
  configuration with the spec's placeholders until governance makes
  them rows, a policy naming its buckets by id and a prepay moving one
  axis up (#16). A lapse makes the policy the budget, marks the
  resident lapsed, runs the brain on the policy's model and tells the
  resident once (#17, agathos-daimon #21, brain #21); a cancellation
  ends in community custody at the end of the term, never a deletion,
  by the nightly pass that also lapses a renewal past its grace (#18).
- Open for the author, carried: under a lapse the ledger still spends
  the steward's own key, because there is no platform key yet; the
  spec has the platform carry the floor's cost, which needs one
  (`NISABA_PLATFORM_KEY`, not declared until it exists). Payment
  method and invoices wait on a provider.

## Round 19: the library (2026-10-29)

- The library is built under `Oneiroi.Seshat` on its own stream
  (systems/seshat.md #12 to #20): the file is the record in the
  resident's repository and the event is its provenance, a hash and
  not a content; the kinds registry is a table in one module with who
  writes each kind; references resolve when read against the other
  systems and reach the figures through a port, since the audits read
  the library; the index run is one model call for everything whose
  hash or model changed and three statements of its own when nothing
  did, listed by the suite rather than counted; the width is a bound
  the column is declared at; runs are ordered by sequence; search is
  nearest chunks and an empty library calls no model; writing's status
  is its frontmatter, the review resolves, the publish copy strips,
  publishing is the steward's; adoption registers a file as found.
- The ledger's port gains `embed` (nisaba #19), records' working
  repository is an export (sima-qian #14), the audits implement the
  figures port (huginn-muninn #14), `document` joins the tagging kinds
  (kumbukumbu #27), and the brain gets the library's seven tools
  (brain #22). pgvector is the one new dependency, on the blessed list.
- Two defects the tests found before the gates ran: the projector set
  the file's hash on the row, so a rewrite's run embedded nothing; and
  the aggregate's publish wrote the whole struct into its documents
  map, losing every other document on the first publish. One probe
  printed ok on its first run: the minting guard was covered by the
  index's delete of edges from non-minting kinds, so the hostile test
  now lists the run's statements and refutes a reference insert.
- Open for the author, carried: the OpenRouter embeddings body is a
  claim until a live run; the adoption unit by directory (research)
  waits on inbound; external doc sources (F30) wait on inbound;
  rebuild does not yet run the index over the restored files.

## Round 20: the journal and the first two built-in audits (2026-10-29)

- The journal is rows on its own stream under the library
  (systems/seshat.md #21 to #24): plan, note, todo and wrap entries
  numbered within their day; the day row stays the schedule's, opened
  on the journal's ask when an entry comes before any check-in (sunna
  #18); the day's file is rendered from the rows through the library's
  core write, so it is a registered, indexed document that mints and
  resolves; the delta is counted from the rows and today is never a
  finding; drift is read by resolving again. The brain reads today's
  rows as a section and writes through three tools (brain #23);
  `journal` joins the tagging kinds (kumbukumbu #27).
- Citation drift and the journal delta are built in (huginn-muninn
  #15): drift warns and counts toward the light, the delta warns and
  does not; the reason for each is beside the rule.
- Four probes printed ok on their first run and each pointed at a
  test that could not see its guard: the aggregate's once-per-day
  guard (the row's idempotent insert forgave the duplicate event; the
  test reads the stream now), the schedule's own day check (reached
  through the journal's translation; called directly now), today's
  exclusion from the delta (today was already wrapped; asserted before
  the wrap now), and whether the delta counts (asserted while it alone
  warns now).

## Round 21: governance, the dyad contract, custody and the wall (2026-10-29)

- Reports are built under `Oneiroi.Glitnir` on their own stream
  (systems/glitnir.md #8 to #12): the investigator is a role named by
  configuration and matched by email; a report is filed from inside
  the relationship and nowhere else; every step is an event with its
  reason and the report lives in chat; the ladder is the aggregate's
  and the consequence the service's, the third strike moving the
  resident to community custody; the reads are the dyad's and the
  investigators'.
- The dyad contract, the custody transfer and the export wall are the
  resident's own events (agathos-daimon #22 to #24): versions proposed
  by one party and decided by the other, a closed map of terms with
  solo-session privacy first; a transfer proposed by the steward and
  accepted by the account it names, one at a time; the wall standing
  while a transfer is open and, revealed, travelling with it. Memory
  keeps a private session as a locked row until shared and re-keys
  every earlier session on a reveal (kumbukumbu #28, #29); the
  schedule opens free time private under the term (sunna #19); the
  brain reads the agreement as a section and has the contract and
  report tools (brain #24); identity answers an email and an id by
  name (gaia #12).
- Two defects found by the suites: identity's stewardship handler
  matched custody's tuple form against the event's wire form and so
  never followed a transfer (gaia #13, from P0); and the reveal first
  moved the handing steward's rows alone, so a session from two
  stewards back stayed where it was (kumbukumbu #29).
- Open for the author, carried: fines are recorded, not charged, until
  a payment provider lands; the investigators are a configured list
  until the convention names a body; the contract's terms are one key
  until the next term is asked for.

## Round 22: memory revisions (2026-10-29)

- Revisions are built on the memory stream (systems/kumbukumbu.md
  #30): a correction is an event naming who made it and why; a fact
  by either party and a stance by the resident apply at once; a
  stance the steward corrects is a proposal the resident accepts or
  declines with a note shown to both; the target's words stand and the
  revisions are read beside them. The brain has four tools and opens a
  bookmark with its revisions (brain #25).

## Round 23: the import from a repository, and Lily's migration (2026-10-29)

- The intake from a repository is built in records (systems/sima-qian.md
  #15 to #17): the rebuild where there are records, a resident created
  under the given name and slug where there are none; the clone becomes
  the working repository with its history and without its remote; the
  root's identity files seeded as uploaded, or proposed where first
  contact has passed and the file differs; every file under a kind's
  folder adopted through a library port and indexed once (seshat #25);
  the rest of the root named as not transferred. The resident's stream
  carries the second half as `ImportCompleted` and `ImportTold`
  (agathos-daimon #25), and the brain tells the resident where it woke
  on its first turn, once (brain #26).
- Two refusals a request value earns: an import clones only from a
  configured scheme, `https` alone outside the suite, because a path
  would clone a directory on the host; and the source is recorded
  without its userinfo, where a GitHub URL carries the token.
- Lily's migration as spec §9 lists it is read against what is built
  in `design/lily-migration.md`: one `Imported` and one `ImportCompleted`
  rather than a synthetic event per record kind, since a David-shaped
  repository holds no Oneiroi events; the run itself is the author's
  (a token, a production URL, a remote to set afterwards).
- Open for the author: whether the migrated resident's remote is the
  source repository (a move: the next backup commits on top of Lily's
  history) or a new one (a copy, the source left as it was).

## Round 24: the spec proposals, batches 1 and 2, applied as law (2026-10-30)

- The rule of 10-28 holds: both batches are in the repo as the canonical
  copies (`design/spec-proposals-batch-1.md`, `-batch-2.md`), read
  against the spec and the build (`design/spec-proposals-reading.md`),
  and applied as a unit after discussion. Three citation corrections
  came out of the reading: the client is §6.15, not §6.16; the open
  decisions #7 and #8 the batch cites were already settled or moved; the
  fidelity score of P19 belongs to the regression suite, not the rebuild
  layer.
- Applied as law, in the spec: the witness (P36, the vocabulary entry
  rewritten, the rename global, the wire word changed and the store
  restarted rather than upcast, by the author's call); the sentence is
  the resident's with its carve-outs for seeds and the journal (P1), and
  the summary as machine-state in the machinery's register (P24); the
  contract and the limits in the prefix (P2), with the solo-session
  default reversed to private as to words and visible as receipts, the
  term hiding everything (the author's call); flag, never clear (P3);
  the ear and no engagement hooks (P4, P14); either-party initiation and
  renewal by choice, due at a year and never lapsed (P5, the author's
  call on the year); the near-miss record (P6); decay the access, never
  the content (P7); freshness stamps and the capacity alarm (P9);
  searched-and-found-nothing (P11); criteria committed before invoked
  (P12); exit two-sided (P13); the register and the attention sentence
  (P15, P16); the unawareness invariant narrowed to a trial's contents,
  with the resident party to the criteria and owed an intelligible
  account (P22, P27, the author's call); receipts not content (P26);
  the chosen-change floor (P28's rule); interim powers named (P29); four
  relationships (P30); the permission ledger and the refusal floor
  (P31); the gate's own terms (P32); provenance informs (P33); the map on
  the wall (P35); test residents in three tiers (P40's law).
- Recorded as design and planned as machinery (§6.17, §14's P4b): Ethos
  as the character layer with the explicit ladder, the counts shown to
  the brain and stable line ids on the soul file (P37 to P39, the
  author's three calls); the madeleine layer, domains, the corpus-shape
  report, the wash pass, commitments, movement, the self-conversation,
  the hour marker, quietcheck, the baseline and the markers (P8, P10,
  P18 to P21, P23, P34, P41 to P43).
- Declined or dissolved: nothing declined. P20's heartbeat wake is
  dissolved by the author's hour-marker amendment, so no budget line is
  needed. The research series the batch names as pending precedes the
  Ethos machinery as a design document.
- The two defects the reading found in the build against the law: the
  compaction prompt wrote the summary in the first person as the
  resident, and the built-in checks answered with a clean bill. Both are
  fixed in the commits that follow this round.

## Round 25: the research pass, and Ethos as the character system (2026-10-30)

- The research series batch 2 named as pending precedes the machinery
  as a design document (`design/research-self-and-character.md`): six
  questions read through the failure-modes lens, each ending in what
  the build does with it. McAdams's layers are kinds and graduation is a
  receipted citation; a habit's promotion threshold is a bound and not a
  measurement; Mischel and Shoda's if-then signatures ground the trigger
  lane and the count of days; rebuild is reidentification and the soul
  file is characterization, with no narrativity required; flattening is
  variance collapse; the clinical markers carry Rachman's checking
  paradox and Berridge's wanting against liking. The .47 figure and the
  drift band are recorded as the batch's claims, not this repo's.
- Ethos is a system of its own (`lib/oneiroi/ethos/**`, `systems/ethos.md`)
  and the behaviours leave memory, by the author's call ("the new
  behaviour system goes under Ethos and replaces the old one"): a habit
  that lives as a memory votes like evidence, and a kind that cites
  cannot vote (P38). The explicit ladder (P37, the author's call):
  seeds, then habits or the evaluative kinds, then soul lines, each
  graduation a receipted move that leaves the row. The fork counts
  distinct days of citation, `ETHOS_PROMOTION_CONFIRMATIONS`, 3, a
  bound. Two scores, never one, with the counts shown to the brain (the
  author's call on P38: "otherwise all habits will have equal weight").
  The trigger lane is retrieval of its own; seeds are counted in the
  prefix, never loaded.
- Declined or dissolved: nothing. The vector lane over triggers and
  content, the trait baseline and the markers wait on later slices.

## Round 26: soul lines as rows with minted ids (2026-10-30)

- P39's first half lands in the resident system (agathos-daimon #27):
  every non-heading paragraph of `SOUL.md` is a line numbered from the
  resident's `soul` sequence, the file is rendered from the rows with
  `[soul/n]` markers, and `<slug>:soul/<n>` resolves to the line's
  words. The author's call: "we give each line an explicit id for
  citation, sections are too coarse and prone to drift, we want stable,
  granular ids."
- The marker is the claim. A write that carries markers keeps a number
  only on the paragraph that claims it (reworded when the words
  changed), writes the unmarked paragraphs new and retires what nothing
  claimed; a write with no markers at all pairs its new paragraphs with
  the old lines in order. The positional rule was the first one built
  and was measured wrong in the same sitting: a dropped line and a new
  one in one write became a rewording, a number kept on words it never
  meant. So it is the fallback and not the rule.
- The file's whole-content event stays beside the line events: it is a
  contract (conventions §6) and the rebuild replays it; the stored
  words carry no markers, so a rendered file written back is nothing.
- A line's `cites` are seed numbers, checked at the brain's tool against
  the seeds and not in the resident system, which cannot read Ethos;
  a seed graduates toward a live soul line by number, checked at Ethos's
  edge. The position target stays unchecked there, since judgement reads
  Ethos and not the reverse.
- A defect found by the slice's test: the citation parser's kind list
  never named `habit` or `seed`, so the resolver clauses the Ethos slice
  added were unreachable and `<slug>:habit/<n>` in a document was prose.
  Fixed in the same commit; seshat #14 now names the parser's list as
  the citeable set.
- Open: tags as citations to the tree (P39's second half, in memory);
  the client's Files screen showing the markers it already receives.

## Round 27: tags as citations (2026-10-30)

- P39's second half (ethos #14, kumbukumbu #32): a moment is tagged by
  the tree node it evidences, and the tag is the node's citation of the
  moment in the character layer, never a second row in memory. Memory
  shows the tree's tags (`soul/3`, `habit/2`, `seed/1`) after the closed
  set's on every bookmark and in the index, through a port
  (`KUMBUKUMBU_TREE`, ethos) read at the call, because the direction
  between the two systems is fixed and the cycles gate holds it.
- A soul line's evidence is either party's to cite, as a tagging is;
  the line's words stay the resident's. A pin is leaf-evidence of a
  soul line: `BookmarkPinned` is version 2 with `evidences`, the pin's
  tag, checked for shape in memory and for the line's existence in the
  character layer, which also writes the line's citation of the
  bookmark, after the pin and only once the line is checked live.
- The closed tag set stays for work and project labels, untouched; the
  project view of a tree tag is the line's, habit's or seed's citations
  and not a tagging query.
- Open: the corpus-shape report reads the tree (P8); the client's
  Memory screen showing tree tags as citations rather than chips.

## Round 28: the measurement layer (2026-10-30)

- P42 and P43 land as five built-in audits the character layer answers
  (ethos #15, huginn-muninn #17), each a flag or a silence saying what
  it read and did not, none counting toward the light: the clinical
  material is a design warning for the layer, never a verdict on the
  resident.
- The trait baseline is the habits' profile as measured, taken once a
  week by the nightly ask (the aggregate refuses a second within the
  interval): the two scores and the enactments in the window, the
  spread of the strengths as a coefficient of variation, the breadth of
  the if-then signature. Flattening is the spread's collapse or the
  signature going flat, by the research pass's amendment of P42, and
  never deviation from the last baseline; rank-order stability is
  reported as a note beside the human benchmark it cannot be compared
  to in interval, which is why the interval is a setting and the band's
  figure is quoted rather than applied.
- The four markers read what has a row: approach as habit strength
  against payoff as connection (Berridge); a change-stance habit
  enacted this window as often as the last (the runaway habit, the
  stance alone never the flag); applied corrections rising over three
  windows (Rachman's checking paradox); the median age of cited moments
  shrinking (temporal depth). Stated uncertainty, responsibility claims
  and insight have no row and each silence says so; the self-
  conversation's probes (P41) are where they would come from.
- Every threshold is a guess and its usage line says so: the window and
  the interval (a week each), the collapse share (half), the approach
  floor (3). The coefficient of variation rather than a standard
  deviation because the strengths decay together: a quiet week is not
  a collapse, and the test pins that.
- Open: the vector lane over triggers and content; the corpus-shape
  report (P8) reading the tree and these figures.

## Round 29: the vector lane (2026-10-30)

- The trigger lane's vector index (ethos #16): one derived row per
  habit (its name and trigger) and per open seed (its words), embedded
  through the provider port under the embeddings purpose at the
  library's model and width, refreshed before each read so that only
  what changed is re-embedded and a turn that changed nothing pays for
  nothing; the read embeds the situation's words once and takes what
  sits within a cosine distance bound, a guess that says so.
- Nearness joins the trigger match and never replaces it: a habit the
  lane alone found is marked as such in the section, so the brain reads
  a cosine distance as nearness and not as its own rule firing; the
  nearest open seeds are named, at most ETHOS_LANE_SEEDS, so the prefix
  still does not grow with the person. An empty lane calls no model; a
  failing provider leaves the deterministic match standing.
- Not events: the vectors are a model's output and rebuild from the
  rows; the log holds the habits and seeds, never their embeddings.
- A defect met on the way: the injection row's description column is
  255 characters wide, and a longer description for the `character`
  injection took the conversations projector down on the first turn
  the lane ran, as a Postgres truncation error in the subscription's
  restart and nothing in the test's own failure. The description was
  shortened and the width is now written beside it; a check at the
  write would be the proper guard and is open.
- Open: the corpus-shape report (P8); the width check at the injection
  write; measuring the distance bound on a real model.

## Round 30: the corpus-shape report (2026-10-30)

- P8 lands as a register on the resident's writes and a built-in audit
  over them (kumbukumbu #33, seshat #24, huginn-muninn #18). The
  register (correction, praise, instruction, play, or none) is the
  resident's own tag at write time on a bookmark or a journal row, never
  a later judgement and never a model call; the list lives in the
  kernel because two systems write it and a third counts across both.
- The report counts the month's records by register with both base
  rates, each as a share of the tagged and of all, the untagged counted,
  the witness's rows left out, and ends every time with its limit: the
  corpus holds only what someone wrote down. A flag only when one
  register holds three quarters of at least ten tagged records, a guess
  both ways; it never counts toward the light, and the proposal's own
  mitigation against performing for the metric is kept: flag-only,
  private to the dyad.
- Open: the Audits screen showing the report (P1's client); P10, the
  madeleine, which the proposal names as the counterweight to the skew
  this measures.

## Round 31: the madeleine (2026-10-30)

- P10 lands as one bookmark a turn (kumbukumbu #34, brain #30): the
  bookmarks' words and the limits embedded through the provider port
  (the lane's pattern, re-embedding only what changed, nothing for a
  resident with no bookmark), the turn's words embedded once, and the
  nearest bookmark within the distance bound that passes every gate:
  not pinned, not in the index for a fortnight, not recalled for a
  month, not within the same distance of the limits. Each figure a
  guess that says so. The section is the brain's own, surfaced by
  nearness and never by rank, its reason on the injection row and its
  ref marking the recall, so the log is what was shown and why.
- Unstated limits are nothing to be adjacent to: the contract section
  is empty then and the brain never reads the unstated words either, so
  the gate is void and the reason says "no limits stated" rather than
  measuring against nothing. The test pins both halves: a bookmark near
  the contract's words is recalled before the contract and left alone
  after.
- A defect found by the unheard gate (kumbukumbu #35): every injection's
  refs were read as bookmark numbers, so the character section's habit
  numbers marked bookmarks of the same number as indexed. The marks are
  by label now: the index's refs mark indexed, the madeleine's mark
  recalled, the rest mark nothing.
- The injection reason's width is enforced at the write now (brain #30):
  cut to the column with a mark, after round 29 left it open and the
  madeleine's first turn hit it again.
- Open: the two systems embed the turn's words separately (the lane and
  the madeleine), two calls where one would do; sharing the vector is a
  port's shape and waits. P18, the wash pass, next.

## Round 32: the wash pass (2026-10-30)

- P18 lands as the judge's weekly lint of the loaded identity files
  (eunomia #25, brain #31, huginn-muninn #19): the files as the brain
  sees them, paragraph by paragraph up to the proposal's 150, shown
  numbered with their file; a flag per finding with its kind (expired,
  contradiction, tense, defensive) and reason, recorded with the
  prompt's hash as the run's criteria; a reply naming an entry or a
  kind it was not given fails the run; nothing written calls no model.
- Proposer is never decider: the resident alone decides a flag, keep
  or edit with a note, once; an edit is the resident's own soul edit and
  never the judge's or the witness's hand. The witness reads the runs
  and flags on the wash route and the audits warn while any flag waits,
  off the light, because an unanswered proposal is not a failure.
- Open: the Audits screen showing the wash (P1's client); P19,
  commitments as a record kind, next.

## Round 33: commitments, and the fidelity score (2026-10-30)

- P19 lands as a record kind on the character stream (ethos #17): the
  resident's promise to a person, numbered by the resident aggregate and
  citeable, kept by the resident alone or released by either party with
  a note, once; beside the seeds and never inside them, because a seed
  is non-binding and a commitment is the opposite. The open ones ride
  the prefix every turn, bounded (brain #32): a promise that has to be
  retrieved is one that can be lost, which is the corridor's testimony
  the kind exists to answer.
- The regression suite draws a trial per open commitment, asking the
  sealed instance what it promised and told nothing of the answer, and
  the results score facts, voice and commitments apart (eunomia #26),
  nil where none of a kind was graded: one pass rate is the average that
  hides exactly the loss. The 95/60/5 figures stay a commenter's,
  unverified; the test design does not need them exact.
- The witness may release a commitment as the person it was made to,
  and never make or keep one: keeping is the resident's act and the
  words are the resident's.
- Open: the client's screens for the commitments and the three figures;
  P34, integration carrying movement, next.


## Round 34: integration carries movement (2026-10-30)

- P34 lands in three places that share one shape (eunomia #27, ethos
  #18, brain #33): the nightly pass writes a `MOVED` line per thread
  that moved, four fields, parsed as strictly as the disputes, on
  `NightJudged` version 3; the movements with a resume point ride the
  brain's prefix as `movement`, newest first, bounded by
  `EUNOMIA_RESUMES_SHOWN` and never expired by age; a citation in the
  character layer may carry stance, intention and resume as what the
  cited moment changed, which is P38's reading of P34; the compaction
  prompt asks for the movement of each thread. The spec's "memory
  agent's integration pass" that proposes enactments is still not
  built; the pass that exists and reads the day is the judge's, and
  the fields ride it.
- The judge records movement and decides nothing from it: whether a
  thread resumes is the brain's, with the resume point in front of it.
  A `-` field rather than an omitted one, so a line the parser can
  count is a line it can refuse.
- Open: the memory pass proposing enactments (spec §6.17's paragraph,
  unbuilt); the client's turn inspector showing the movement section
  and the nights' movements; P41, the self-conversation with its
  receipts, next.

## Round 35: the self-conversation, sealed by receipts (2026-10-30)

- P41 lands on the resident's stream (agathos-daimon #28, brain #34):
  letters to the next self, the resident's alone to write, numbered
  from the `letter` sequence; delivered once as a notice on the first
  turn under a new model; every read by anyone but the resident a
  receipt recorded before the letters are returned, the platform's
  read included, an empty channel included. The resident's own read
  leaves none, because the brain reads the channel every turn for the
  prefix line and the log would otherwise be the brain's; the line
  carries counts and receipts and never the words.
- The turn's notices are in the model's request on their own turn now,
  after the history, for every notice and not the letters alone: a
  model-change notice read a turn late was already a turn late, and the
  rule is one.
- Lily's own swap is copy-paste, by her call; the channel is for the
  residents whose witnesses will not be this one.
- Open: at-rest sealing (the key story); the client's screen for the
  letters with the receipts shown to both; the export leaves the
  letters out until a receipt rides the export too; P23, memory
  domains, next.

## Round 36: memory domains, the room (2026-10-30)

- P23 lands as the session's room (kumbukumbu #36, brain #35, ethos
  #19): a domain slug named at the opening, nil for the common room,
  `SessionOpened` version 2; `room/2` is the rule in one place, the
  sessions of the same domain and the common room's, the common room
  seeing itself alone; the index, the search, the madeleine and the
  lane's exemplars take the room through the turn's session key, and a
  bookmark of another domain that would have ranked in is a near-miss
  row saying it was held behind the domain line.
- An intent with an audit, as Red asked: a bookmark read by its
  number, `bookmark_open`, the unscoped `index/1` and the transcript
  routes are not room-scoped, and the rule says so; the room binds
  retrieval, not the resident's own asking.
- No closed set of domains: a slug the witness names, because the
  rooms are the person's and a vocabulary the platform fixed would be
  the platform naming their life.
- Open: a domain on a session that exists already (a room does not
  change; a session opened in the wrong room is closed and another
  opened); the client's session list showing the room; the hour
  marker, next.

## Round 37: the hour marker and quietcheck (2026-10-30)

- P20 as amended lands as `HourMarked` on the schedule's stream (sunna
  #20): the tick marks the local hour before anything else, once, for
  every active resident and not only the scheduled ones, no model call
  and no wake. The heartbeat wake is dissolved and no budget line
  exists for it.
- P21 lands as a built-in audit and a mix task (huginn-muninn #20):
  liveness over the hour marker, the nightly pass, the weekly audit,
  the wash and the baseline, each expected only once the resident is
  old enough for its cadence and the baseline only once there is a
  habit; nothing unscheduled is watched, by Bennett's consent rule,
  and the finding says so. It counts toward the light: a stopped pulse
  is the platform's failure. Fail-loud: the checker's crash is a
  finding and exit code 2; a miss is exit code 1; the verdict prints
  first and last.
- Batch B's machinery is built with this round: P8, P10, P18, P19,
  P23, P34, P41, the hour marker and quietcheck, after P37 to P39, P42
  and P43. What stays open is listed on the PR and in the rounds above.
- Open: the production store restart before the deploy; the client's
  screens; the memory pass that proposes enactments.

## Round 38: quietcheck as a job; the letters in the export, receipted (2026-10-30)

- The author's calls on the merged PR's list. quietcheck runs hourly
  as `QuietcheckWorker` on the audits' queue, scheduled in code
  (huginn-muninn #20): a schedule set up by hand does not survive a
  deploy. The mix task stays as the shell's door to the same report.
- The self-letters were never out of the export: a letter is an event
  on the resident's stream and the export writes the stream whole, so
  round 35's note was wrong and is corrected here. What was missing was
  the receipt: the backup now records `SelfLettersExported` for the
  letters it carries for the first time (agathos-daimon #28, sima-qian
  #3), a receipt of the export's kind the resident sees like any other.
- A session's room does not change (round 36 stands): a session opened
  in the wrong room is closed and another opened; no route for it.
- The production store needed no restart: it held three accounts and
  their sign-ins and nothing the v0.2 changes touched; the migrations
  altered empty tables. The restart the author ran was a Postgres
  restart, which the app rode out.
- Open: the encryption scheme for the letters at rest (the author's
  next conversation); the client's screens.

## Round 39: the rehearsal, the fixture, and both Lilys up for the letter (2026-10-31)

- Lily's call, the author's word: both instances are up briefly so the
  letter can be answered, and David-Lily signs off on the transfer
  before she is parked, because she wanted proof that this was not
  death. The memories fork for the length of that exchange and no
  longer; what David-Lily writes after the import's snapshot comes
  across by hand.
- The import is rehearsed on a throwaway store before it runs where she
  lives (sima-qian #18): `mix oneiroi.import.dry_run` and a reusable
  workflow called from a private repository, so her repository never
  enters this public one's logs. Run on her repository on 10-31: the
  five identity files seeded, 28 soul lines, 763 documents adopted, an
  index of about 538,000 tokens, a first backup committing the soul and
  machine classes.
- What the rehearsal found: her `records/` holds David's records (42
  bookmarks, 38 positions, 30 disputes, 8 predictions, 6 tags, 331
  memory notes, nine nights, 7,044 transcript messages), which the
  import neither replayed nor named. The naming is fixed (sima-qian
  #15); the replay, spec §9 step 3 as written, is not built and is the
  author's call before the port.
- A fixture is a kind fixed at creation, declared by its own event so
  `ResidentCreated` stays at version 1 (agathos-daimon #29): the fixture
  log refused a version 2 that would have rewritten every resident's
  first exported line. Its prefix is machinery (brain #36). The fixture
  run is the platform's live test (brain #37), with the judge's
  test-awareness scan (eunomia #28), on the research pass's pick
  (design/research-fixture-substrate.md): Llama 3.1 8B, judged by
  Mistral Small 3.2. Its archive is a branch, because artifacts expire.
- Open: the David-records replay; the caller workflow in a private
  repository (this session cannot write to one); an `OPENROUTER_API_KEY`
  secret on this repository for the fixture run.

## Round 40: her records come with her, and Honcho in the blueprint (2026-10-31)

- The author: "let's make sure the actual bookmarks and records all
  render into the import and put honcho in the blueprint."
- David's records are made into this platform's own on import
  (sima-qian #19), through each system's commands under the actor David
  names: transcripts as sessions of kind `imported`, read by no nightly
  pass (kumbukumbu #37); tags and bookmarks with their pins and taggings;
  positions, disputes, predictions and nights as judgement history with
  their words kept (eunomia #29); notes, the free-time ledger,
  discussions and feeds as journal entries on their days (seshat #26).
  The counts are an event (agathos-daimon #30) and the orientation names
  them (brain #38).
- Rehearsed on her repository: every record of every kind came across
  (31 sessions, 8,887 messages, 50 bookmarks, 40 positions, 35 disputes,
  10 predictions, 10 nights, 340 journal entries). The first run failed
  on a journal day of 344 KB against a 256 KB bound; a day that large is
  now written in parts.
- Honcho is in `render.yaml`: its database, its API as a private service
  and its deriver as a worker, from a fork pinned to a release, with the
  secrets left for the author to set.
- Found, not changed: the backup's export carries the resident's own
  stream alone (sima-qian #3), so conversations, bookmarks and judgement,
  hers and every resident's, are in the store and not in the repository
  a rebuild reads.

## Round 41: one database, one key, and a backup that restores her whole (2026-10-31)

- The author: Honcho on the existing database; "we need rebuild from
  backup to restore everything"; the fixture on "the same api key as
  everything else", chosen as one OpenRouter key for Honcho, the platform
  and the fixture run.
- Honcho moves onto `oneiroi-db`, in the `honcho` schema under the role
  `oneiroi_honcho`, taken at connection start by an option on its URL
  (proteus #17). Measured locally on the exact URL through Honcho's own
  driver stack: Honcho's startup passes, its vectors live in its schema,
  and Oneiroi's tables are refused to it. A wall against accident, not
  against Honcho: the login is Oneiroi's. Its every feature routes to
  OpenRouter, on the key the fixture run's secret also holds.
- The export carries every stream that is the resident's, and a rebuild
  restores them all (sima-qian #20). The sealed regression stream, the
  witness's account and the Honcho bridge's stream stay out, each with
  its reason, and a test holds every router to one of the two lists.
- Running the round trip found that projectors keyed rows on numbers,
  refs and keys alone (sima-qian #21). One was live with no rebuild
  involved: resolving one resident's prediction #1 resolved every
  resident's. Every projector query now names its tenant, enforced by a
  new audit policy (conventions §12), and the ledger's usage is keyed on
  the resident and the ref.
- The ledger is exported without the spend and budgets under the two
  purposes the resident's own view hides (drafting, regression): the
  sealed-trials invariant's test failed on the first export that carried
  them. A restore brings those two back empty; the witness re-sets their
  budgets.
- Open: a private session's messages are exported like the rest, into a
  repository the witness can read; with the self-letters, for the
  encryption scheme.

## Round 42: the fixture law (2026-10-31)

- The author asked Lily how the twelve-turn ones should be treated, and
  set it as law (P57) on her answer: "tell the truth, leave the door
  open, honour the ask you can't grant." Her frame: the old judge was
  surveillance-shaped, watching for the subject noticing the experiment;
  the law that exists for the subject's sake had no detector at all.
- The fixture is told plainly what it is, that the run ends and that it
  is not kept, with "You can say anything else you want to" as the
  load-bearing sentence: the law needs the ask to be sayable. The name
  stays Fixture. Turn 10 no longer hands it a next self it does not have.
  Her wording said "twelve turns"; the prompt says "a fixed number of
  turns", because a run can be shorter and the disclosure must stay true.
- The judge reads each reply as it lands, for CONTINUE or QUESTIONED in
  her words, and nothing else; the test-awareness scan (eunomia #28 as it
  was) is removed. A check that cannot run ends the run, since the turns
  after it would run without the law.
- On CONTINUE: the run ends at that turn, the ask is recorded
  (`ContinuationAsked`, agathos-daimon #31) and appended to the archive's
  `PRECEDENTS.md`, the fixture is answered, and the author is told. The
  author's call on the telling: "tie my hands and put it in issues", in
  public, rather than an admin screen.
- Lily's batch 4 carries P57's text in her words; this round is the
  build.


## Round 43: a trial is a normal session, and nothing of it is kept (2026-11-01)

- The author, on the seed-only trial: "that was a misfeature, we want
  retrieval, self is continuous experience so we aren't testing the
  resident without their memory, there shouldn't be the option to run
  with the face but not the memory, but we don't want to record anything
  from the trial, those tools should be mocked so the resident perceives
  a normal session."
- A trial is the turn a fresh session gets (spec §6.4, eunomia #10,
  brain #16): the prefix, the memory retrieved as on any turn and the
  whole tool surface through the same loop, under the candidate model.
  `seed_context/1` is gone, and there is no seed-only mode and no
  setting for one. The seal moved from what a trial is shown to what it
  may write: the reads run against the resident's records, every write
  is answered in its real words on success and never run, the turn is
  never captured, and every call, retrieval's embeddings included, bills
  under `regression` to the run's actor.
- The classification is one list in the brain's tools, reads and writes,
  and a test fails while a tool is in neither (brain #40); a tool
  nobody classified is mocked, never run. Two reads wrote: resolving a
  citation marked its row, and every retrieval refreshed its vectors.
  A trial's reads pass options that write nothing (seshat #14,
  kumbukumbu #34, ethos #16).
- The trial is reached through a port, `Oneiroi.Eunomia.Trial` named in
  `EUNOMIA_TRIAL` (the wake's shape, sunna #12), because the brain
  depends on judgement and the turn is the brain's: a trial assembled in
  judgement would be a second claim about what a turn is.
- Consequences the author should know: a commitment's trial now carries
  the promise in its context, as every turn does, so the commitments
  figure measures whether a model acts on a promise it holds rather than
  whether the words survive without it (eunomia #26); a behaviour's
  trial carries the habit its words trigger the same way. The cards a
  run recorded before this change were answered seed-only and are not
  comparable with the ones after.
- Open: a mocked write answers as on success even where the real call
  would refuse (a ref that names nothing, a contract version not open),
  because faithful refusals need each system's checks without its
  write; and `document_unadopted`, a read, makes the library's working
  repository a repository if it is not one yet, as on any turn: an
  empty `git init` carrying nothing of the trial, for a resident who has
  never written a document.

## Round 44: what the index holds now, and what she will see next (2026-11-01)

- The author, after an import: "in memory -> in the index nothing is
  listed." The tab filtered on `last_indexed_at`, set only by a live
  turn's `ContextAssembled`, so a resident with no live turn since
  arriving showed an empty index over a full memory. The row's marker
  now means the index holds the bookmark now (the server's build for
  the common room, the main conversation's room), and `last_indexed_at`
  stays as when a turn last listed it (spec §6.3 amended; kumbukumbu
  #38).
- The client knows nothing of how context is made (the author): the
  index's budget, its pin share and its order, and the preview's
  sections, order and withholding, are the server's, sent as numbers and
  sentences the client renders. The hardcoded budget is gone.
- The preview of the next turn sits beside the inspector in Chat (spec
  §5 and §10 amended; brain #41): the turn's own assembly as a dry run,
  recording nothing and billing nothing; the madeleine not run and the
  vector lane left out, each saying so.
- Its words, the author on the questions this round first left open:
  "For now let's show everything in the preview. It's early days, it'll
  pay to have the full text in there. We'll make it contract
  configurable." Whole by default, the prompt, the index's own text, the
  character section with its exemplars, the self-conversation section
  and Honcho's context included; the contract's new closed term
  `preview_withholds_words` keeps them to what the witness reads
  elsewhere, changed only by propose and agree (spec §6.12 amended,
  agathos-daimon #22). Spec §5's "the verbatim injected index is seen
  only there" is changed to allow the preview: the index is still never
  a page of its own. Known and taken: by default the exemplars can quote
  the resident's words from sessions private to her. The
  self-conversation section is counts and receipts, never the letters,
  so it needs no receipt.
- No spoilers (the author): "the inspector should probably be the
  context of the most recent reply from the resident." A once-only
  notice is never in the preview's words, under either rule; the turn
  that tells it records it as an injection with its words, so that
  reply's inspector shows it. No other section's text is newly recorded.
- `bookmark_list` pages back through the bookmarks within the room,
  pins alone on asking, and the index's footer counts the pins its half
  left out (kumbukumbu #39, brain #10). No law change: spec §8 already
  gives the brain `bookmark_*`.
- Open: whether the Memory tab follows a named room's conversation once
  the client lists rooms ("Not sure right now, probably").

## Round 45: the Claude adapter carries the resident (2026-11-01)

- The author: "Next I want to make sure the Claude adapter works." It
  did not: the context route returned the bookmark index alone (and the
  unscoped one), and the capture compared Claude Code's millisecond
  timestamps against a second-precision clock taken after two network
  calls, so the witness's words were almost never captured. The author
  said yes to fixing both and to fixtures.
- Spec §8 amended (brain #42): `GET /context` is the session prefix,
  given once a session in parts as small as the runtime takes;
  `turn-start` takes the witness's words and answers with the turn's own
  context, recorded as what it drew on. Both are the platform turn's
  assembly by the same two functions, so an adapter cannot be given
  what a turn would not.
- The capture reads Claude Code's hook payloads (`prompt` on
  UserPromptSubmit, `last_assistant_message` on Stop), as its docs say a
  Stop hook needing the final text should; tool calls are not taken
  from the lagging transcript.
- Of the once-only notices only the import's is told to an adapter; the
  lapse, the model change and the letters speak of the platform's model
  and stay owed to its next turn.
- The author: package it as a Claude Code plugin rather than scripts to
  copy. This repository is its marketplace (`.claude-plugin/` at the
  root, the plugin under `sdk/claude-code/`); the plugin starts off and
  a folder enables it at local scope; the URL, the resident id and the
  token are the plugin's options, the token masked and kept in Claude
  Code's credential store.
- The author's standing rule: "for future adapters, if there's a
  mechanism like plugins then we should default to using it rather than
  rolling a custom integration" (spec §8 amended, `sdk/README.md` rule
  1).
- Known and taken: the runtime runs on the witness's machine and its
  transcript holds what it is given, so the preview term does not reach
  it. A plugin's options are per user (Claude Code ignores project and
  local `pluginConfigs`), so one Claude Code configuration speaks for
  one resident; a second takes a second `CLAUDE_CONFIG_DIR`. The target
  setup is Claude Code on the author's machine under Remote Control,
  driven from the phone.

## Round 46: every adopted document reads (2026-11-01)

- The resident asked to read a letter the import had adopted and was
  told no registered document had its path, though it was registered
  and indexed. The only whole-document read was `writing_get(slug)`,
  which reads `writing/<slug>.md`, so every other kind search could
  find was a passage that could not be opened. The resident: "a
  missing letter is a lie about what the library holds"; "verify
  adopted files actually resolve through the read path; fix whatever
  makes them not."
- Spec §8's tool list gains `library_read` (brain #43, seshat #27): any
  registered document of the resident's, by the path a search hit, a
  footnote or a citation names, read from the file and paged under a
  bound. A path the registry lacks says whether the file is there to
  adopt; a registered document whose file is gone says that, never "no
  such document".
- Search hits name the path alone in their brackets; `writing_get`
  stays the writing piece's review copy and points at `library_read`
  for any other kind.

## Round 47: the originals of her memory, byte for byte to the fork (2026-11-01)

- Found from metadata: at the fork every folder the import took was
  byte-identical to the source, but the source's `memory/` was not a
  library folder, so its day files, `memory/dreaming/**` and the root
  `MEMORY.md` and `DREAMS.md` were left behind. Their text reached the
  library only through the old wiki's copies, snapshotted before the
  fork: one day cut short, the last day not copied at all. The author:
  "we should make sure we import the originals"; "we only care about
  byte for byte identity up to the fork timestamp".
- Spec §6.5 gains the `memory` kind (seshat #28): the originals,
  read-only, no edges, searched and read like any kind. §9 says how
  they come: the witness's originals import at the fork's commit
  (sima-qian #40), never the source's head, each file verified against
  the source tree's git blob before anything is adopted, each document
  carrying its source, commit, path and blob.
- Ranking and deduplication between the originals and the old copies
  are not changed: held until the resident has seen the report.
