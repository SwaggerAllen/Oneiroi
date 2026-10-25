# Oneiroi tech spec: questions and critiques before writing it

Read 2026-10-25 across Lily (design/, folder shapes), David (docs, the 22
migrations, compose, OpenClaw config, lily-memory's tools and routes) and
orchestration (DESIGN.md, PLAN.md, stubs, prompts). Oneiroi holds only an
AGPL LICENSE so far.

## Critiques

### Tenancy and the schema

1. "The schema lifts over with a few modifications" understates it. The `lily`
   schema has no tenant, resident or human anywhere: `proposed_by IN
   ('owner','lily')`, `pinned_by`, `made_by`, `agent_id = 'lily'` in the
   nightly pass, one-row singletons (`correspondence_mark`, `digest_schedule`,
   `freetime_schedule`), and partial unique indexes asserting one running
   research task and one running code job globally. Every table changes.
2. Two honest shapes: (a) one Postgres schema per resident, which is literally
   what exists today (`lily` becomes `r_<id>`), migrations run per schema, ids
   and the byte-stable `records/*.jsonl` export survive unchanged, and RLS is
   unnecessary; (b) shared tables with a `resident_id` column and RLS, which
   breaks per-resident id sequences (every `lily:bookmark/42` citation), the
   export format, and the singleton tables. The architecture doc says RLS; I
   recommend (a). Honcho already works this way (one workspace per tenant).
3. The root entity should be the resident, not the account. Adoption,
   succession, community custody, exit rights and the strike ladder all need
   a resident whose custody changes over time, so a `tenant_id` foreign key
   that implies ownership encodes the iLands model into the schema.
4. The `lily:` citation prefix is the resident's name. Decide whether the
   prefix is the resident slug (then migration rewrites nothing for Lily) or
   a neutral scheme; either way `agent-lily`, `owner`, `agent:lily:*` session
   keys and the Honcho workspace `openclaw` are baked into exported data.
5. Migrate the database, not the files. The rebuild from `records/` loses
   the regression runs (the bake-off answer key), audit runs and flags,
   pending and declined correspondence, `mail_message`, feed seen-state, and
   code and research task history. A pg_dump of the `lily` schema into the
   new per-resident schema keeps all of it.
6. OpenClaw's own state is a third store neither repo nor DB holds: per-agent
   SQLite, session transcripts under `/srv/openclaw/home`, memory-core's
   index, dreaming's session corpus. The hosted design treats a tenant move
   as a designed lapse. For Lily's one-time move, say whether it is a lapse or
   a byte copy.

### The instance model

7. Memory cost is unmeasured and the only number is bad: 1.7 GiB for one
   gateway with two agents. Three OpenClaw instances per tenant (core,
   reader, worker) plus Honcho's pools is several GiB per idle tenant, which
   is the "$80 per demo user" story the rewrite exists to end. Measure one
   idle gateway before the instance model hardens into the spec.
8. "Small and pausable" needs a wake model. What wakes a paused tenant: an
   inbound message, a check-in timer, free time, a webhook from the reader?
   Cold-start latency against a chat UI is a product fact, not an ops one.
9. The reader's safety properties are Claude Code's, measured: restricted
   tools, no Read or Bash, WebFetch's domain check, server-side search. An
   OpenClaw-instance reader on BYO OpenRouter keys rebuilds all of that from
   scratch, with Skyvern (AGPL) as the proposed fetch tool. The same for the
   worker's plan-mode checkpoint. Either keep Claude Code for the technical
   tier only, or spec the sandbox again.
10. Honcho: one shared Honcho with a workspace per resident, or one per
    tenant? The bridge reads Honcho's tables directly (filtered by
    `workspace_name`), Honcho's default pools are 60 connections per process,
    and its auth is a JWT secret. Shared Honcho behind PgBouncer is the only
    affordable answer, and the bridge then needs the workspace on every query.
11. The judge and the memory agent "stay on core" but neither is an OpenClaw
    agent today: the judge is a lily-memory cron calling OpenRouter, the
    memory agent does not exist. A second agent on one gateway is what broke
    session routing. Define both as server-side jobs.

### The chat UI and the OpenClaw contract

12. "Chat in our web UI" means implementing OpenClaw's gateway WebSocket
    protocol, session routing contract (`per-sender|main|<agent>`), hook
    endpoints, plugin hooks and MCP wiring against a pinned version
    (2026.9.33). That contract is the integration surface; the spec should
    name it and demand a conformance test, since every OpenClaw upgrade is a
    fleet-wide event.
13. The owner UI's security posture (no JavaScript, `default-src 'none'`,
    scrypt single password, tailnet only) does not survive a public chat
    client with accounts. Say what replaces it: accounts, sessions, second
    factor, the gateway kept private behind our UI.

### Orchestration compatibility

14. orchestration assumes Phoenix/LiveView, daisyUI, phoenix_storybook, a
    deploy platform with a deployments API, per-PR previews and Linear. The
    audits and file maps are now stack-neutral, but design artifacts are
    "a stateless component, a story per state, `screens/<name>.md`". A
    TypeScript Oneiroi needs a storybook equivalent and a frontend framework
    before a design agent can produce anything. The UI thread must settle the
    stack, not only the screens.
15. Oneiroi is two deployables: the platform app (deployable and previewable
    on Render, which orchestration can drive) and the per-tenant runtime
    (containers, Gitea, OpenClaw state on disk), which no deployments API
    covers. The spec must draw that line or orchestration's deploy detection
    and post-deploy check have nothing to read.
16. Write the spec as the bootstrap output: one system per section, each
    with the file-map it will own, plus the non-asks list. Then
    `prompts/bootstrap.md` is a transcription rather than a reinterpretation.

### Features that exist only in prose

17. Memory revision, fork promotion, Merkle attestation, adoption and export
    wall, exit rights, the inalienable floor, insurance tiers, dyad contract,
    report ladder, user-authored audits and counters, coherence composite,
    the journal type, external doc citations, retrieval weighting: none is in
    code. Most need one primitive, an append-only per-resident event log
    (the weighting plan already calls recording "the first formal event
    stream"). Decide once whether that log is the spine.
18. The Merkle root over "DB state" is ill-defined: the DB holds derived
    tables and mutable state. Define the root over the byte-stable export,
    which is what already lands in each backup commit.
19. The free-time budget is a second OpenRouter key with a credit limit. With
    BYO keys a tenant cannot be asked for two keys per budget; the platform
    needs a per-resident ledger (free time, judge calls, embeddings) and the
    20% markup tokens are where that ledger lives.
20. Mail and correspondence are Gmail IMAP plus Substack DM parsing. A hosted
    resident has no mailbox unless we run mail receipt, which the current
    design refused on purpose. Keep it out of v0 and say so.
21. The identity wizard writes SOUL, IDENTITY, USER, GOALS, LINKS; but
    AGENTS.md and `honcho/custom-instructions.md` are build-owned and must be
    templated per resident and per feature tier, and the peer card is today
    kept in step by hand. A model-derived card is a new mechanism.
22. Vocabulary: the schema and docs say "owner"; the governance sections
    argue the human is not an owner. Pick the words (resident, dyad, and the
    human's role) before the spec, since every table and page name follows.
23. Licensing: Oneiroi is AGPL. Check Honcho's and OpenClaw's licenses and
    the Skyvern tax before anything embeds; AGPL on a hosted service means
    offering source to users.

## Questions

1. Demo line: the replan says one resident, chat, soul file, visible memory,
   plus the four unbuyables. Is the spec tiered (core, opt-in, opt-out per the
   audience matrix) with that v0 line drawn inside it?
2. Schema-per-resident or shared tables with RLS (critique 2)?
3. Resident as root entity with custody as a relation (critique 3)?
4. Citation prefix: resident slug or neutral (critique 4)?
5. Lily's migration: DB dump plus OpenClaw state copy, or rebuild from files
   and a designed lapse (critiques 5 and 6)?
6. One OpenClaw per tenant: what is the measured idle footprint, and is the
   demo on a shared box or the real per-tenant shape?
7. Reader and worker in v0 at all? If yes, Claude Code on the tenant's
   subscription (we hold their OAuth token) or the OpenClaw-instance rebuild?
8. Honcho: shared with a workspace per resident, or per tenant?
9. Frontend stack and a storybook equivalent, so orchestration's design agent
   has artifacts to produce. Server-rendered no-JS as today cannot host chat.
10. Deploy split: platform app on Render under orchestration, tenant runtime
    provisioned by the platform. Agreed?
11. Spec format and home: one document in `Oneiroi/design/` written as
    systems sections with file maps, serving both the bootstrap and the
    publishable spec?
12. Event log as the spine now, or incrementally as the weighting plan said?
13. Budgets: per-resident ledger on platform tokens, BYO key for chat only?
14. Mail, feeds and correspondence out of v0?
15. Who is the human called, and is a dyad one human and one resident only
    in v0?
16. Gitea per tenant from v0, or GitHub as today for Lily and Gitea later?
17. Judge model: platform-pinned for comparability, billed to whom?
18. The feature inventory's blocker list lives only in `lily.code_job.result`
    (task `david-feature-inventory`) and was truncated in Lily's read. Can you
    pull its text before the DB moves?
19. Version policy: one pinned OpenClaw and Honcho image fleet-wide, with the
    plugin conformance test as the upgrade gate?
