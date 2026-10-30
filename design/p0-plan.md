# Oneiroi: P0 build plan

How the spine gets built. Companion to `oneiroi-spec.md` §14 (the
roadmap, cited as *spec §n*) and `conventions.md` (cited as
*conventions §n*), which hold the design and the code rules; this
document holds P0's sequence and its reasons, in Catapult's
`build-plan.md` shape: every ordering states why.

P0 ends with one resident, created through the API, exported to a
repository on GitHub with attested backup commits, and rebuilt from that
repository into a fresh database whose export is byte-identical. No chat,
no memory, no client beyond a skeleton. What P0 proves is the spine and
the pipeline that will deliver everything after it.

## Standing decisions for P0

- **The gates predate the work.** P0.1 to P0.5 are attended (this
  session with the author), and the pipeline delivers from P0.6. Same
  reason as Catapult's Phase 1: reconciliation trusts green, so every
  check must exist, and have been watched failing, before an unattended
  merge trusts it. Identity is the one domain system written attended,
  by the author's decision: they want to read the auth code as it is
  written. It lands before the hookup rather than after, because attended
  work on `main` once the pipeline runs is out-of-band by orchestration's
  definition and may only land with nothing in flight; written first, the
  pipeline's history begins with the verification ticket and the project
  is never parked for its own authors.
- **The substrate is lifted from Catapult as a copy, never as a
  dependency.**
  `components/daedalus` there is Apache-2.0 and about 4,900 lines: the
  component behaviour and its registry roster, the composer that fails on
  collision, the config registry with env, static and secret sources, the
  error kinds, the VM guardrails, health, seeds, the injected clock, and
  the audit task with its AST-grade checks (wall clock, process name,
  secret in log), declarations, license inventory and boundary apps. That
  is conventions §4, §5, §8, §10 and half of §13 as running code, each
  rule carrying the measurement that produced it. Rewriting it would
  re-derive rules from their wording and lose the measurements. It lands
  as `components/daedalus`, a path dependency renamed to the `Oneiroi.*`
  namespace, with its licence kept, and `sdk/` consumes the same
  package: the audit scopes per mix project, and the SDK needs the audit
  without ever holding core code (conventions §1). A copy, not a
  dependency: no hex package, no git reference, no upstream remote. It is
  Oneiroi's code from the first commit and diverges at once (the roster
  rows below). `systems/daedalus.md` records the Catapult commit it was
  taken from so a later session can diff against it by choice; nothing
  obliges one to. The live dependency on Catapult's neighbourhood is
  orchestration, pinned at `@v1`, and that one the roadmap chose; the
  substrate adds no coupling to it, since nothing in the pipeline knows
  what component macro a project uses.
- **Four projects exist from the first commit, each empty and
  enforced**: the core at the root, `components/daedalus`, `sdk/` and
  `client/`. The gate block in conventions §2 names all four, and a gate
  line that fails because its directory is absent is "fixed" by deleting
  the line. An empty project that passes its own block is cheaper than
  that conversation.
- **The event store runs on Postgres in every environment, tests
  included.** Catapult switches to Commanded's in-memory adapter for dev
  and test. Oneiroi cannot: the replay suite, the stream-naming scope and
  the rebuild round trip are claims about the real store, and an in-memory
  fake that agreed with them would be the fake conventions §9 warns
  about. The cost is a store reset per test run, which P0.2 measures.
- **Ticket grain is the whole deliverable.** P0's three systems are three
  tickets, after one verification ticket. Reconciliation verifies a diff
  against an argument, and a system-sized argument is what it is built to
  check.
- **Nothing in P0 calls a model, and nothing in P0 declares the model
  port.** The port and its fake land with the brain and the ledger in P1,
  which is the first thing that meters a call. The `model_port` audit
  check lands in P0 anyway and reports that it covers nothing, so the
  first call site in P1 is already watched.
- **The export never carries the resident's uuid.** Files are keyed by
  slug and per-resident ids. This is what lets a rebuild be a new resident
  (spec §6.2: an import is always a new resident) and still produce an
  export byte-identical to the source for every day before the `Imported`
  event. Without this rule the round-trip test cannot be stated.
- **Measurements P0 takes are written down as it takes them**, in the
  system docs and this file's last section, because the configuration
  waits on them and a number nobody measured is a guess that survives
  review.

---

## P0.1 Skeleton and substrate (attended)

The repository layout and everything that makes the gate block true on
a tree that does nothing.

1. `.tool-versions`: Erlang 27, Elixir 1.17 (otp-27), Node 22, exact
   patch versions. CI reads the same file strictly.
2. `mix phx.new` at the root with no HTML, no LiveView, no assets, no
   mailer, no dashboard: the client is React and the mailer is a decision
   for the ticket that first sends mail. Boundary on, as `check: [apps:
   [...]]` rather than `type: :strict`, for the reason conventions §4
   records; the application root is a top-level boundary of its own, so
   the core and the web layer need not depend on each other.
3. `components/daedalus`: the port of Catapult's substrate under the
   `Oneiroi` namespace, Apache-2.0 licence file kept, Catapult-specific
   prose trimmed. The roster gains what conventions §4 names that it
   lacks (`usage:` and the bound-or-measured `tag:` on a `config/0`
   declaration, and the `settings` check that holds them) in the one
   place each belongs; `events/0` and `externals/0` with its kill switch
   were already rows in the roster.
4. `Oneiroi.System`: the `use` macro over the component behaviour, with
   the standard skeleton (export module, `Config`, `Supervisor`, `Store`,
   `Events`, `TestSupport`) and `defexport` riding telemetry spans.
5. The gate block of conventions §2, verbatim, in `CLAUDE.md`, `ci.yml`
   and `pipeline.config.json`, and the `gates` audit check that reads all
   three. `ci.yml` is Catapult's with a Node setup step beside the BEAM:
   `pull_request` into `main` only, Postgres service pinned to the major
   P0.2 chooses, `fetch-depth: 0`, exact-key dependency cache with no
   fallback, the self-arming pipeline audit.
6. `mix oneiroi.audit` v0 with every check Daedalus carries plus
   `gates` and `skips`, registered by Apsu through
   `policies/0`; `prompts` waits for the model port in P1, since it is a
   rule about that port's call sites. `mix oneiroi.audit.all` at the root
   over the three mix projects, exiting 1 on an unresolved one.
7. `/health` with the git SHA and per-system readiness; `Dockerfile`
   whose CMD migrates then starts; `render.yaml` with the previews
   block; the first deploy, so the deploy loop exists before anything
   deploys.
8. `systems/apsu.md` and `systems/daedalus.md` with file maps, and
   the `.reasons.md` siblings.

Exit: CI green on an application that answers `/health` and nothing
else, and every gate probed red once. The probes, each asserting its
edit matched exactly once before the run: a `DateTime.utc_now` inside
an aggregate module (`wall_clock`); a bare `name: __MODULE__`
(`process_name`); an `unwrap/1` inside `Logger.info` (`secret_in_log`);
one word changed in `CLAUDE.md`'s gate block (`gates`); a `@tag :skip`
with no key (`skips`); a compile-time dependency between two boundaries
(the ratchet); a cycle (xref); a warning (compile). A check with no
instance in the tree to judge prints that it covers nothing rather than
`ok`, which is Daedalus's own rule for inert states and the only
honest answer on an empty tree.

## P0.2 The persistence spine (attended)

Everything in conventions §6, §7 and §12 that a system is built on top
of, built before any system exists so the first system cannot be built
without it.

1. **One Repo**, owned by Apsu; Commanded's application
   and EventStore on Postgres with its own schema; Oban. The store reset
   per test run, measured.
2. **Two database roles**: `oneiroi_migrator` owns the schema and runs
   migrations; `oneiroi_app` is `NOBYPASSRLS` and is the only role the
   release connects as. The Repo wrapper sets the resident (or account)
   scope per transaction from the principal and refuses a query with no
   scope set; a cross-tenant job sets scope per resident explicitly and is
   named in its system doc. Measured here: whether Render's managed
   Postgres lets the owner create a second role. If it does not, the
   fallback is `SET ROLE` to the app role in `after_connect`, which gives
   the same guarantee from one credential, and the measurement is
   recorded either way.
3. **Migration lint** as the `tables` audit check: every table has one
   owner by prefix; every projection table carries `resident_id` or
   `account_id` and a row-level policy; migrations are additive and
   forward-only.
4. **The event validator** at the command edge: every event carries its
   actor and, where a model produced it, the model slug; every decision
   event carries a non-empty `note`. Refused, not warned.
5. **`events/0` with versions**, the pure upcaster pipeline applied on
   read, and the fixture-log harness that replays `records/events/*.jsonl`
   files from `test/fixtures/` and asserts every historical shape still
   folds. Empty of fixtures until P0.6 writes the first.
6. **The purity floor** enforced: the injected clock from Daedalus,
   seeded randomness, ids generated at the command edge. The `wall_clock`
   check now has aggregates to parse.
7. **The configuration module** (spec §6.16): every setting declared with
   a default, a usage line and the `bound` or `measured` tag, validated
   and reported at boot, a missing required value naming itself. The
   `settings` audit check.
8. **The tenancy test harness**: `TestSupport` seeds two residents under
   two scopes, and a helper asserts a query under one scope sees nothing
   of the other. The assertion has nothing to see until P0.6 and is
   written now so P0.6's ticket inherits it rather than inventing it.
9. **The cost harness**: a statement recorder around the Repo and a
   per-row budget assertion, so P1's capture path arrives into it.
10. **Trace context** threaded through Oban and PubSub by the platform's
    wrappers; structured JSON logs to stdout with nothing content-bearing.

Exit: a persistence layer with no tables of its own and every rule
enforced. Probes: a projection migration without a policy (`tables`); an
event constructed without an actor (the validator); a `Repo.all` with no
scope (the wrapper); a second event version with no upcaster registered
(`events/0`); an untagged numeric setting (`settings`); the fixture
harness fed a log with one field renamed. Measurements recorded: the
store reset time, the second-role answer, the full gate set's wall clock
on CI.

## P0.3 The client and SDK skeletons (attended)

1. `client/`: Vite, React 18, TypeScript, Storybook, with the design
   system's `tokens.json` imported as the theme and one story that
   renders a token swatch, so `npm run build-storybook` builds something.
   `npm run lint`, `typecheck` and `test` configured. The OpenAPI client
   generates from `/v1/openapi.json`, which P0.4 is the first to
   populate, and the typed channel client is a stub with its type.
   Phoenix serves the built storybook on previews, which is what Design
   review reads.
2. `sdk/`: a mix project, Apache-2.0, depending on Daedalus and
   nothing from the core, with `licensing: [allow: ...]` declared and the
   `license` check armed. It holds the adapter behaviour's module names
   and nothing else until P1 writes the contract.

Exit: both blocks in the gate set run and pass. Probes: a copyleft
dependency added to `sdk/mix.exs` (`license`); a story whose variation
name is not a state name (the export build); a type error in `client/`.

## P0.4 identity (attended)

Written with the author watching, by their decision, and before the
hookup for the reason the standing decisions give. It depends on no other
system, and every later system scopes by the principal it creates.

Accounts with password and TOTP; argon2 hashes; sessions as random ids
with the hash stored, thirty-day expiry; `__Host-` cookies, `HttpOnly`,
`Secure`, `SameSite=Strict`; `Origin` checked on every mutation; the CSP
allowing the client bundle and nothing else; failed logins slowed, never
locked. The Account aggregate's v1 events. The witnessing relation with
a start and an end, and the community as a principal. The JSON API token
for scripts. `/v1/openapi.json` with its first routes, so the client
generates. The self-hosted setup task that creates the one account.
Contract tests per role token, asserting exactly which routes each may
call. Sobelow has its first real surface here.

## P0.5 Orchestration hookup (attended, `SETUP.md`)

A runbook rather than tickets, because the pipeline does not run until
it is done. Catapult's `SETUP.md` is the template and most lines carry
over.

1. **The docs the bootstrap would have produced**, written by hand since
   there is no existing architecture doc to split: `systems/<slug>.md` for
   the sixteen systems of spec §6, each with a file map, its standing
   decisions carried from the spec, and initial-versus-target state made
   explicit (a system doc for a system P5 builds is a file map, its
   decisions and the line "not built; see spec §6.n"). `screens/*.md`
   stubs from the UI pass's screen list (spec §10). `CHANGE.md`,
   `non-asks.md` with the schema and the refusals the spec already
   records, `tests/manual/README.md` with the `covers:` front matter
   shape.
2. **`pipeline.config.json`**: the state map, `designOwnedPaths`
   (`CHANGE.md`, `screens/**`, `storybook/**`, `systems/*.md`,
   `docs/*.md`, `tests/manual/**`), `componentPaths`
   (`client/src/components/**`), `qualityGates` identical to the gate
   block, `deploy.provider: render` with the service id, the `state`
   block, `staleClaimGrace: 20m`, `citationShorthands` for `spec` and
   `conventions`.
3. **The stubs**: twelve of the fourteen from orchestration's
   `examples/stubs`, the five that run the project's own commands with
   `ci.yml`'s environment block, Node beside the BEAM, and the Postgres
   service. `pipeline-pages-provision` and `pipeline-preview-cleanup`
   are not copied: Render builds and expires the preview per PR from
   `render.yaml`, and Catapult retired both on the same move.
4. **Orchestration's own touch-ups** (spec §11), landed in that repo by
   the author in the same sitting: the design-artifact list as a
   parameterised block, the design prompt phrased for React components
   and CSF stories, the class audit reading `.tsx` base names under
   `componentPaths`, the stub environment block installing Node.
5. **The tracker**: a Linear project for Oneiroi under the `ORC` team,
   which is where Catapult's project lives too (its config names that
   team's id); `pipeline setup --apply` to create any state or label the
   team lacks; the team and project ids in the config.
6. **The metronome**: the `PROJECTS` entry in the Worker's config, the
   `DISPATCH_TOKEN` repository list, the GitHub webhook for workflow runs
   and deployment statuses.
7. **Secrets and settings on the repository**: `LINEAR_API_KEY`, a model
   credential, `PIPELINE_REPO_TOKEN`, `AGENT_GITHUB_TOKEN` with this repo
   on its list, `RENDER_API_KEY`, `PIPELINE_STATE_TOKEN`; Actions may
   create pull requests; branch protection requiring `ci`;
   `PIPELINE_KILL_SWITCH` understood as the park switch.
8. **The verification ticket**: a README touch, moved to Designing by
   the author, watched through design, dev, reconcile and deploy
   unattended. Its Done is this phase's exit, and the moment the ci
   audit step stops printing "skipped".

Exit: the verification ticket is Done; the backlog holds P0.6 and P0.7
as tickets and P1 as coarse placeholders. Tickets are filed on the
author's ask (orchestration's rule), from the drafts in the last
section.

## P0.6 resident (pipeline ticket)

The Resident aggregate on `resident-<id>`, with the v1 events P0 needs:
`ResidentCreated`, the lifecycle transitions with their reasons,
`CustodyTransferred`, `Imported`, `ExportWallSet`. The slug, bound to
the witness's account through the witnessing relation. Per-resident id
sequences allocated by the aggregate: a counter per kind held in
aggregate state, so an event that mints a citeable id carries it without
a second event and replay reproduces it exactly, which the property
asserts, as does the one that two residents never interleave. The
`resident` projection under its policy. Creation through the API with a
name and a slug only; the creation flow with its threshold and gifts is
P1 (spec §6.2), because the threshold collects a key the ledger does not
yet exist to hold. The two-residents bleed test from P0.2 becomes real
here. The first fixture log in `test/fixtures/sima_qian/records/events/` is written
from these events, so the replay harness has a history from the day the
first event shape exists.

## P0.7 records (pipeline ticket)

The export, the attestation, the git port and the rebuild (spec §6.10),
over the resident stream only: account events are the platform's and
never enter a resident's repository.

Export to `records/events/<day>.jsonl` with keys and rows in a fixed
order and a watermark a minute behind; the Merkle root over the export
tree; backup commits by class with the trailers `Oneiroi-Sequence` and
`Oneiroi-Root`, and a run that fails after committing the rest when
something wrote where nothing should (David's rule). The git port with
two providers: a local bare repository for tests, and GitHub over HTTPS
with a witness-supplied fine-grained token stored encrypted. Secrets at
rest need a library, which is a decision for the author (below). Rebuild
as `mix oneiroi.sima_qian.rebuild <repo>`: replay into a fresh store under
a new resident with the `Imported` event appended, refusing a store that
already holds the resident, printing by name what cannot come back. The
attestation check as an Oban job that recomputes the root on a schedule
and raises `RootMismatchDetected`, since there is no wake yet to hang it
on. The round-trip test: export, rebuild into a throwaway store, export
again, byte-identical for every day before the import.

Exit for P0: that test green in CI, and the same sequence run by hand
once against a real GitHub repository, with the commit trailers read off
GitHub and the rebuild done on a second database.

---

## Decisions, settled 2026-10-26

1. The substrate is lifted as a copy, as the standing decisions say,
   after the author asked whether lifting chains Oneiroi to Catapult's
   lifecycle. It does not: a copy has no upstream, and the measured rules
   and their tests are what a rewrite would lose.
2. The event store runs on Postgres in test.
3. **The Postgres major** is read off Render's default when the blueprint
   is created, pgvector confirmed on it, and CI and `render.yaml` pinned
   to it in one commit. Spec §2.1's "16 or later" permits this; Catapult
   pinned 18 the same way because CI was cheaper to move than a database.
4. **Secrets at rest** were to use `cloak_ecto` (MIT) with a deployment
   key from the config module. Superseded in the build (decisions log
   round 9): the gate refused its two open advisories, and
   `Oneiroi.Apsu.Vault` over `:crypto` took its place under the same
   key.
5. **The GitHub provider's credential in P0** is a fine-grained token the
   witness pastes, scoped to a repository they created; a GitHub App that
   creates repositories and installs deploy keys comes with Gitea.
6. **The tracker** is a project under the `ORC` team.
7. **Identity is written attended**, as P0.4.
8. **P0.6 and P0.7 were built attended too**, in one pass with the spine
   (decisions log round 9), because the author asked for the rest of P0
   in one go; their tickets become the verification ticket's successors
   only as follow-ups the pipeline files later, not as the first work it
   delivers.

## Ticket drafts (filed on the author's ask)

Each in orchestration's issue shape: an imperative title, the argument,
what it touches, open questions stated.

- **Verify the pipeline on a README touch.** Argument: nothing after
  this merges unattended until one ticket has. Touches `README.md`.
- **Build the resident aggregate with per-resident id sequences.**
  Argument: P0.6 above; the id rule is what makes citations survive a
  rebuild, and it must exist before the first citeable thing does.
  Touches `lib/oneiroi/agathos_daimon/**`, `systems/agathos-daimon.md`,
  `test/fixtures/sima_qian/**`.
- **Build records: export, attestation, the git port and rebuild.**
  Argument: P0.7 above; the repository is the portability promise and the
  round trip is the only test of it. Touches `lib/oneiroi/sima_qian/**`,
  `systems/sima-qian.md`. Open question: decision 5.

## Measurements P0 records

Filled in as they are taken, each with its date and where it was taken.

| Measurement | Where it is needed | Value |
| --- | --- | --- |
| Full gate set wall clock on CI | whether the gate block is affordable per PR | 2m19s on a cold cache, PR #6's first run (`40270464624`, 2026-10-26): checkout, BEAM and Node setup, every gate line including the client's `npm ci` and storybook build |
| Event store reset per test run | decision 2 | 3s for drop, create and migrate (Oban, the event store schema, the application role, three projections), measured locally 2026-10-26 with the shell timer; the 89-test suite runs in 15.8s after it |
| Second database role on Render's managed Postgres | P0.2 step 2 | not measured; the build took the `SET ROLE` shape, which needs no answer (systems/apsu.md #12) |
| pgvector on the chosen Postgres major | decision 3 | |
| Export bytes and seconds per thousand events | the nightly export's budget | |
| Preview environment cost per hour | `render.yaml`'s `expireAfterDays` | |
