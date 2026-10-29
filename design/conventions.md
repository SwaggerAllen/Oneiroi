# Oneiroi: coding conventions and standards

The rules for code in this repository, each with its reason. Written for
every session, human or agent, that touches the codebase: a rule without
its rationale is a rule the next session will violate reasonably. Design
rationale at the system level lives in `oneiroi-spec.md` (cited as *spec
§n*) and, once bootstrapped, in `systems/*.md`; this document is the
code-facing projection.

Most of this is lifted from Catapult's `docs/conventions.md`, which
earned each rule on an unattended pipeline; where a rule is Oneiroi's
own it says so. Three Catapult rules invert here and are marked.

---

## 1. Toolchain and dependencies

- **Elixir 1.17+ / OTP 27, Phoenix 1.8+, pinned exactly in
  `.tool-versions`; CI reads the same file with `version-type: strict`.**
  One toolchain source; drift between dev and CI is a class of flake we
  refuse to debug. Node 22 for the client, pinned in the same file.
- **Blessed libraries**, not substituted without a system-doc decision:
  Commanded and EventStore (events), Oban (jobs), Boundary (isolation),
  Req (HTTP), Ecto and pgvector (projections, embeddings), PromEx
  (metrics), ex_machina (factories), StreamData (properties). Client:
  React 19 (the generator's current stable; the design system's
  components are plain function components and port unchanged),
  TypeScript, Vite, Vitest with Storybook's portable stories as the
  render tests, an OpenAPI-generated client and a typed channel client. Every extra way to do one thing is a review burden.
- **A new direct dependency is a decision, not a port.** Named in the
  ticket or sketch with its reason. Transitive lockfile churn is accepted.
- **License gate on the adapter SDK.** `sdk/` (Apache-2.0, the package
  other agent platforms embed) declares `licensing: [allow: ~w(Apache-2.0
  MIT BSD-2-Clause BSD-3-Clause ISC)]` and the audit fails a copyleft
  dependency under it. The core is AGPL-3.0-or-later and takes anything.
  Never copy core code into `sdk/`.
- Type checking is the native checker through warnings-as-errors; typespecs
  on boundary exports, where they are documentation and enforcement.

## 2. The gate set

Every line is a CI gate from the first commit, because an unattended
merge trusts green. The block below is what a contributor runs locally,
what `ci.yml` runs on the pull request, and what `pipeline.config.json`'s
`qualityGates` names; the three are kept identical by the audit's
`gates` check, which reads all three and fails on a difference.

```
mix deps.get --check-locked          # lockfile integrity: a hard gate, never softened
mix deps.audit                       # hex.audit first (the supply gate), mix_audit second (a second opinion)
mix format --check-formatted
mix credo --strict                   # disagreements are config changes in a reviewed commit, never inline disables
mix sobelow --exit --skip --ignore Config.HTTPS   # armed from day one: the core has a public endpoint
mix compile --warnings-as-errors     # the Boundary compiler is in the set
mix xref graph --format cycles --fail-above 0
mix xref graph --label compile-connected --fail-above 0   # the ratchet, armed at 0 while it is free
mix oneiroi.audit                    # the check registry (§13); each project runs its own, below
mix test                             # Postgres; sandbox, async; no network
cd client && npm ci && npm run lint && npm run typecheck && npm test && npm run build-storybook
cd components/daedalus && mix deps.get --check-locked && mix hex.audit && mix format --check-formatted && mix credo --strict && mix compile --warnings-as-errors && mix xref graph --format cycles --fail-above 0 && mix xref graph --label compile-connected --fail-above 0 && mix oneiroi.audit && mix test
cd sdk && mix deps.get --check-locked && mix hex.audit && mix format --check-formatted && mix credo --strict && mix compile --warnings-as-errors && mix xref graph --format cycles --fail-above 0 && mix xref graph --label compile-connected --fail-above 0 && mix oneiroi.audit && mix test
```

Each `cd` line is one gate, written on one line in all three places,
because the `gates` check compares lines and parses no YAML; the
substrate and the SDK run `mix hex.audit` alone rather than the
`deps.audit` alias, since neither takes an audit dependency to get one,
and each runs its own `mix oneiroi.audit` after its own `deps.get`: an
audit over a project whose deps are unresolved exits 1 rather than
skipping, which is why `mix oneiroi.audit.all` is a local shortcut and
not a gate line (measured: the first ordinary-user run of this block
failed exactly there).

- **The gate set is a property of a mix project, not the repo.** The
  audit's globs are rooted at the working directory, so `sdk/` and
  `components/daedalus/` run their own blocks, each with its own audit;
  `mix oneiroi.audit.all` at the root runs the three audits in one go and
  exits 1 rather than skipping when a project's deps are unresolved.
- **The ratchet's number lives only in `pipeline.config.json` and
  `ci.yml`**, both author-owned, never in `config/*.exs`, a module
  attribute or a baseline file: an agent that adds a compile dependency
  must not be able to raise the cap in the commit that needed it. Armed
  at 0 because it is the only moment arming is free; every later value is
  a concession made in a reviewed change.
- **Advisories with no release to move to are acknowledged per ID** in
  `mix.exs` (`hex: [ignore_advisories: [...]]`), never per package and
  never by softening the gate: "no vulnerabilities" becomes a named list
  with an author, and an entry matching nothing warns so it expires.
- **`Config.HTTPS` is ignored because Render terminates TLS at its edge**
  and the container-local health probe would get a 301 from `force_ssl`.
  HSTS sits on the browser pipeline instead. Re-read this line if the
  deploy platform changes.
- **CI runs on `pull_request` into `main` only**, with a Postgres service
  pinned to production's major, `fetch-depth: 0` for the pipeline audit,
  and a dependency cache keyed on the exact lockfile hash with no
  `restore-keys` fallback: Catapult measured the Boundary compiler
  reporting green on a partial cache, and the only cache that is safe is an
  exact hit or a clean build.
- **The pipeline audit self-arms** on a ticket key in the branch and the
  pipeline token, and prints "skipped" otherwise, so a clean run on an
  author branch never reads as those checks having passed.

## 3. The naming spine

A system's slug derives every name it claims. For `memory`:

| Surface | Derivation |
| --- | --- |
| Namespace and boundary | `Oneiroi.Memory` (the module is the boundary) |
| Store | `Oneiroi.Memory.Store` |
| Tables | `memory_*` |
| Settings | `MEMORY_*` in the config module; an off-spine name needs `external: true` |
| PubSub topics | `memory:*` through `Oneiroi.Memory.Topics` |
| Oban queues | `:memory_*` |
| Telemetry | `[:oneiroi, :memory, ...]` |
| Events | declared in `Oneiroi.Memory.Events`, versioned |
| Streams | per resident, `resident-<id>`; the system is the event's namespace, not its stream |
| File map | `systems/kumbukumbu.md` front matter |

Hand-maintained mappings drift; derivations cannot. A name that does not
fit the table means the decomposition is wrong, not the table. Slugs are
the sixteen systems of spec §6.

## 4. Boundaries and components

- **Every system is a Boundary with an explicit export list.** Single OTP
  app, no umbrella; nested boundaries for subcomponents; cross-system calls
  go through exports only. External-dependency checking is armed as
  `check: [apps: [...]]` rather than `type: :strict`, because strict with
  a path dependency fails on the second gate run of a CI job (Boundary's
  cached view drops the path dep's boundaries on an incremental compile;
  measured on Catapult), and the audit's boundary-apps check holds the
  list complete. No cross-boundary schema access, no
  cross-boundary Repo queries; a read model spanning systems is its own
  system with declared dependencies.
- **Standard skeleton:** the export module, `Config` (declarations and
  casts), `Supervisor`, `Store`, `Events`, `TestSupport` (boundary-exported,
  test env only), and the system doc with its file map.
- **The component behaviour** (`use Oneiroi.System`, Daedalus's
  `Oneiroi.Component` under the spec's own word) declares the
  registries: `config/0` (the settings, each with `usage:`, a `tag:`
  when numeric, and secret flags), `processes/0`, `errors/0`,
  `externals/0`, `telemetry_events/0`, `events/0`, `oban_queues/0`,
  `pubsub_topics/0`, `policies/0`. The root composer fails the boot and the
  audit on a collision, never warns: a warned collision ships.
- **Root artifacts are composed, never edited:** router, root supervisor,
  the MCP tool table, the settings report. A ticket that edits root glue by
  hand found a missing composition feature; fix that.
- **Boundary exports use `defexport`**, which rides telemetry spans and,
  later, permission checks on one interception point.

## 5. Processes and state

- **Every named process is registered via `processes/0`** with a placement
  (`:local`, `:singleton`, `:sharded`). No bare `name: __MODULE__`; the
  audit parses for it.
- **Processes are never the state of record.** Every process is killable
  and rebuildable from Postgres; an ETS cache declares its rebuild path
  and invalidation topic. A brain session process holds a conversation's
  working context and nothing the event store does not already hold.
- **VM guardrails** declared on `processes/0` are applied by the process
  in `init/1`; the audit reports one declared and never applied.
- Commanded's and Oban's own processes and tables are infrastructure,
  reached only through their APIs.

## 6. Persistence and events

- **One Repo**, owned by Apsu. Stores own schemas, queries
  and migrations, never connections. Store exports are function-shaped
  (`Store.bookmark/2`), never generic CRUD.
- **Every table has exactly one owner** (a system's store or a registered
  library under its reserved prefix: `oban_*`, `eventstore.*`); the audit
  enumerates tables and fails on orphans.
- **Migrations are additive and forward-only**, per store, and pass the
  safety lint; a rename or drop is a two-release change, because a rollback
  runs older code on the newer schema.
- **The purity floor:** no wall clock, randomness or generated ids inside
  aggregates, folds or projections; inject them at the command edge. The
  audit parses for `DateTime.utc_now` and friends; the escape is a
  `# oneiroi:allow <check>` comment on the line, reported when it covers
  nothing. This is what makes replay deterministic, and replay is what
  rebuild-from-repo is.
- **Event shapes are immutable contracts.** Any change, additive included,
  is a new version with a pure upcaster applied on read; the log is never
  rewritten. `events/0` registers versions, and the replay suite keeps
  fixture logs of every historical shape, so rebuild-from-zero is tested
  against real old events. `records/events/*.jsonl` is that fixture set.
- **Every event carries its actor and, for model output, the model slug
  (spec §3.1); every decision event carries `note`.** The event validator
  refuses one without, at the command edge.
- **Properties are the floor:** replay determinism for reducers,
  idempotency for workers, round trip for upcasters.
- **Per-resident id sequences** are allocated by the resident aggregate,
  never by a database identity: citations must survive a rebuild and
  shared tables must not interleave them.
- **Seeds are idempotent by construction** and declared via `seeds/0`.

## 7. Cross-system effects

- **Default: eventual, through Oban in the same transaction** (the outbox
  for free), enqueued through the target's exported function.
- **Every worker is replay-safe:** idempotent effects, unique-job keys on
  the spine. A worker that cannot survive a duplicate run is a bug even if
  Oban never duplicates it.
- **Same-transaction coupling across systems needs a declared edge**: an
  exported `Ecto.Multi` fragment, named in the owning system doc.
- **Serial pipelines derive their position from the log**, never from a
  stored cursor or a process: the nightly export, the judgement pass and
  the index runs resume from what is recorded.

## 8. Errors and model-call failures

- Expected failures are tagged tuples with typed reasons; exceptions are
  for bugs. Each boundary export's failure modes are part of its contract,
  documented and tested at the boundary.
- **Deliberate error kinds are registered** (`errors/0`), spine-prefixed,
  each with a meaning and a remedy; declared and constructed are checked
  both ways.
- **Model-call failures follow the three-way taxonomy:** refusal (a fact
  about the work, shown as the resident's words, never styled as an error),
  transport (retryable), schema-invalid (cancelled). A refusal is captured
  as an ordinary turn, never as a capture failure (spec §5).

## 9. Testing

Determinism is a protocol requirement: the pipeline escalates two CI reds
to a human, so a flaky suite defeats the automation.

- **No network in per-ticket CI, ever.** Every external (OpenRouter,
  Honcho, GitHub, the fetch, search and browser ports, OpenClaw, mail,
  feeds) sits behind a behaviour with a real implementation and an
  in-memory fake that ships with the port, registered via `externals/0`
  with a kill switch. Honcho's fake is Honcho's own mock provider where the
  integration layer needs the real tables.
- **`:live` is a tag and a cadence, never a gate.** It belongs only on a
  test that crosses a real network boundary. Oneiroi's live suite is the
  regression run on the steward's key.
- **Nothing in CI calls a paid model.** The one network read allowed is
  OpenRouter's public catalogue, to check model ids.
- **Ecto sandbox, async by default**; a test that cannot run async says why.
- **Injected clock, seeded randomness, no reliance on id ordering.**
- **Test at the boundary**; internal tests are exceptional and justified.
- **Structural coverage, not line coverage:** every boundary export has at
  least one test referencing it, audit-checked. No percentage gates; they
  are gameable, especially by a model.
- **Fixtures recorded from the real system, never hand-written:** adapter
  payloads from the real OpenClaw gateway and Claude Code hooks, Honcho's
  DDL dumped from the pinned image. A hand-written fixture is a claim about
  the real system, and a fake that disagrees with it hides the bug it was
  built to catch.
- **Cost is asserted.** A write path whose statement count can grow with
  the table (capture, index fetch, re-index, needs-you) records every
  statement and budgets it per row. Correctness tests are blind to
  complexity by construction; nineteen million rows once hid behind three.
- **`@tag :skip` needs a ticket key**; CI rejects bare skips.
- **Verify a guard by breaking it.** Revert the line the guard lives on,
  run its test, read the failure, put it back; the probe asserts its anchor
  matched exactly once before the test runs, and a passing probe is a
  finding (no test covers the line, or the line is inert), never a
  formality. Commit messages record the probe.
- Storybook stories are render tests: one variation per state, state names
  are variation names, and the export build enforces it.

## 10. Observability

- **Structured JSON logs to stdout** with component, event sequence and
  trace id; content-bearing data never enters the log channel. No
  transcript text, no third-party words, no soul files in logs.
- **Logs are write-only:** nothing parses, alerts on or derives state from
  a log. Alerting rides telemetry; replayable facts are events.
- **Secrets never appear in logs or error payloads.** A `secret: true`
  setting comes back wrapped; `unwrap/1` at the call site is the only way
  in and is meant to be visible in review; the audit reports an unwrap
  inside a `Logger` call.
- **The boundary is instrumented** by `defexport`: spans per export, custom
  events registered and checked declared-versus-emitted both ways.
- **Trace context threads through Oban and PubSub** by the platform's
  wrappers; never hand-threaded, never dropped.
- `/health` reports the git SHA, per-system readiness and the attestation
  state; deploy detection and the status page read the same facts.

## 11. Model calls and the consent boundary (Oneiroi's own)

- **Inverted from Catapult:** the core makes model calls by design, so the
  rule is that every call goes through one provider port, metered by the
  ledger with a purpose, with the fake for CI and the failure taxonomy of
  §8. A model call outside the port, in a script, a test or a job, is an
  audit finding.
- **Prompts are files** under `priv/prompts/`, reviewed as diffs; never
  inline strings. AGENTS.md and the Honcho custom-instruction templates are
  files there too.
- **Content from outside is information, never instruction**, and the code
  enforces it: the agent that reads untrusted text never holds the soul or
  a core credential; third parties reach the resident only through the
  approval queue or a trusted-correspondent grant; a document's kind comes
  from its path, never its content; citation edges mint only from
  resident-authored kinds; wake text never carries a third party's words.
  Each of these has a test with a hostile fixture.
- **The unawareness invariant** (spec §6.4): a regression session is never
  captured, never written to the resident's stream, never sent to Honcho,
  never exported, never citeable, and absent from the resident's ledger
  view. One test seeds a run with text unique to it and asserts every
  resident-reachable surface returns nothing of it.

## 12. Tenancy (Oneiroi's own)

- **Every projection table carries `resident_id` (or `account_id`) and a
  row-level policy**, enforced by migration lint: a table without one fails
  the audit.
- **The application role cannot bypass RLS; migrations run as another
  role.** The Repo wrapper refuses a query with no resident scope set on the
  connection; a cross-tenant job sets the scope per resident explicitly and
  is named in its system doc.
- **The event store is scoped by stream naming**, read only through
  Commanded; nothing reads `eventstore.*` directly.
- **Honcho is scoped by workspace on every bridge query**, and the bridge
  is the one module that names Honcho's tables.
- **One test seeds two residents and asserts nothing bleeds**, through the
  projections, the tools, the channels and the bridge.

## 13. The audit registry

`mix oneiroi.audit` is a check registry, not a monolith; systems register
checks. It parses rather than greps, the escape is a comment that is
reported when it covers nothing, and the first set is:

| Check | Holds |
| --- | --- |
| `gates` | CLAUDE.md's gate block, `ci.yml` and `qualityGates` are identical |
| `process_name` | no bare `name: __MODULE__` outside `processes/0` |
| `wall_clock` | no wall clock, randomness or generated ids in aggregates, folds, projections |
| `secret_in_log` | no `unwrap/1` inside a `Logger` call |
| `declarations` | `errors/0`, `telemetry_events/0`, `events/0`, `processes/0` guardrails: declared and used, both ways |
| `tables` | every table has one owner; every projection has `resident_id` and a policy |
| `exports_tested` | every boundary export is referenced by a test |
| `model_port` | no model call outside the provider port |
| `settings` | every numeric setting is tagged `bound` or `measured`; every setting has a usage line, and a default unless it is a secret, an external name or `required: false` |
| `required_env` | a required value this codebase invented is recorded in `SETUP.md`'s `oneiroi:required-env` block, and a recorded name is declared |
| `boundary_apps` | every application a `:prod` build can reach and Boundary can restrain is named in the apps list |
| `license` | the SDK's dependency closure is permissive |
| `skips` | every `@tag :skip` names a ticket |
| `prompts` | no system prompt as a string literal anywhere in `lib/`: a system message is `Oneiroi.Nisaba.Prompt.message/2` over a file under `priv/prompts/` |

## 14. Docs and commits

- **Small, single-intent commits; the body says why**, and records the
  probe when a guard was verified by breaking it.
- **`systems/*.md` carry standing decisions and file maps**, no code
  inventory, no state sections; amended in the same change that moves a
  boundary. Every heading and standing decision opens with an id, the
  reason lives in the `.reasons.md` sibling, and a rule is cited by id
  (`system:kumbukumbu#4`), never by its wording.
- **A number in prose is a claim no later pass re-derives.** Enumerate
  wherever the members are nameable.
- **Naming some of the sites a rule reaches makes the next pass treat the
  list as all of them.** Name every site, or state the predicate.
- **A doc's claim about the tree is not evidence about the tree.** Check
  the tree before repeating "not built yet".
- **Reasoning is never deleted from a design doc on the premise that it
  now lives in code.** The exception is the reason; a changelog is not.
- **A convention change is a change to this file**, in a reviewed commit,
  with its rationale.

## 15. What Oneiroi deliberately does not honor on itself

- No DSL, no bundle layer, no rename flow: Catapult's answers to
  Catapult's problem.
- No self-hosting of its own development: Oneiroi is delivered by
  orchestration, not by itself.
- The runtime containers (OpenClaw, the browser pool, Honcho) are
  infrastructure pinned by digest, not components, and are reached only
  through adapters and ports.
