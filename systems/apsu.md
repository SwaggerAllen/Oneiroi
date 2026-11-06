---
paths:
  - lib/oneiroi/apsu/**
  - lib/oneiroi/apsu.ex
  - lib/oneiroi/kernel/**
  - lib/oneiroi/system.ex
  - lib/oneiroi/boot.ex
  - lib/oneiroi/application.ex
  - lib/oneiroi.ex
  - lib/oneiroi_web.ex
  - lib/oneiroi_web/endpoint.ex
  - lib/oneiroi_web/router.ex
  - lib/oneiroi_web/api_spec.ex
  - lib/oneiroi_web/controllers/error_json.ex
  - lib/oneiroi_web/controllers/helpers.ex
  - config/**
  - priv/repo/migrations/*_add_*.exs
  - test/support/**
  - test/oneiroi/kernel/**
  - test/oneiroi/apsu/**
  - test/oneiroi/platform_test.exs
  - test/oneiroi_web/health_test.exs
  - Dockerfile
  - render.yaml
  - deploy/**
---

# apsu

**The platform.** Akkadian, AHP-soo.

> "When in the height heaven was not named, / And the earth beneath did not yet bear a name, / And the primeval Apsû, who begat them, / And chaos, Tiamat, the mother of them both,— / Their waters were mingled together," — Enuma Elish, Tablet I, lines 1–5, trans. L. W. King, The Seven Tablets of Creation (1902)

Apsu is the freshwater deep beneath the world in Babylonian cosmology: the earth floats on it, the springs rise from it, and Enki (Ea) builds his house on it and lives there. In the poem Apsu is also the first father, and the one Ea overcomes to make that house.

The platform (fleet pins, the configuration module, deploy, the status page) is named for what everything rests on and nobody sees: the deep the ground floats on. The provisioner raises runtimes out of these waters, and this is where Enki lives. Gaia already has the earth; the platform is what is under it.

Fleet pins, the configuration module, deploy, observability, the status
page (spec §6.16). In P0.1 it is the one system: the roster, the boot,
the endpoint, the health plug and the two audit checks that are
Oneiroi's own.

## #1 Owns

The system roster (`config :oneiroi, :components`) and `Oneiroi.Boot`,
which validates it and loads every declared setting before the root
supervisor starts; `Oneiroi.System`, the macro every system adopts; the
composed `Oneiroi.Application`; the endpoint, the router and the `/v1`
scope; `/health`; the `gates`, `skips`, `tables`, `free_text`, `error_site`
and `projector_scope` audit checks (`Oneiroi.Apsu.Policies.*`); the
Dockerfile and the Render blueprint. The kernel under
`lib/oneiroi/kernel/`: the Repo and its migrator, the scope, the event
and command macros with the actor middleware, the projection and router
macros, the Commanded application and the event store, the worker, the
clock, the vault. The projections' kernel tables (Oban, the event store
schema, `projection_versions`) and the application role.

## #2 Standing decisions

- **#3 Settings are declarations, and every one carries its reader.** A
  `config/0` entry has a `usage:` line, a `tag:` when numeric and a
  default unless it is a secret, an external name or opted out; the
  audit's `settings` check holds it (conventions §13). The two settings
  this system declares in P0.1 are the listener's port (a bound) and
  the cookie secret (no default; recorded in `SETUP.md`).
- **#4 The port is `APSU_HTTP_PORT`, never `PORT`.** `PORT` is the
  platform's idea of a listener; this is the app's own, and
  `render.yaml` sets both to one number so the probe and the socket
  cannot disagree.
- **#5 The health plug runs ahead of the router as a function plug.** A
  module plug on the endpoint lands a compile-time dependency on the
  core module and moves the compile-connected count off zero; the
  function-plug form does not (measured on Catapult's endpoint).
- **#6 Boundary checking is `check: [apps: [...]]`, not `type: :strict`.**
  Strict with a path dependency fails on the second gate run of any CI
  job, because Boundary's cached view drops the path dep's boundaries
  on an incremental compile (measured on Catapult: twelve forbidden
  references and a red build). The apps list is held complete by the
  audit's boundary-apps check, which derives what a :prod build can
  reach from the tree.
- **#7 The `gates` check reads three literal fences and parses no YAML.**
  `CLAUDE.md`'s block opens with `oneiroi:gates`, `ci.yml`'s region sits
  between `# oneiroi:gates` and `# oneiroi:gates end` with one single-line
  `run:` per step, and `qualityGates` is the JSON list. A multi-line
  `run:` in the region is refused rather than guessed at: a YAML parser is
  a dependency the check does not take, and a region it cannot read is a
  region it must not pass.
- **#8 The `skips` check has no escape.** An allow tag would be a second
  way to skip without a ticket, and the check exists to leave one.
- **#9 Logs are JSON in production and the default formatter elsewhere.**
  `logger_json`'s basic formatter on stdout (conventions §10), with the
  trace id `Oneiroi.Worker` and `Oneiroi.Apsu.PubSub` carry put in
  the metadata and nothing content-bearing.
- **#12 Two database roles from one credential.** `DATABASE_URL` is the
  migrator's; `Oneiroi.Repo` takes `SET ROLE oneiroi_app` on every
  connection, a role created `NOLOGIN NOBYPASSRLS` by a migration, so
  the application cannot bypass row-level security or run DDL whatever
  code reaches it. The second-role answer on Render's managed Postgres
  is not yet measured; this shape needs no answer, which is why it was
  chosen (plan P0.2 step 2).
- **#13 Every query runs under a scope, or raises.** `Oneiroi.Scope`
  holds `{:resident, id}`, `{:account, id}` or `:platform` on the process
  and sets it on the connection for the transaction; `Oneiroi.Repo`'s
  `prepare_query` raises `UnscopedError` without one. The platform scope
  is taken by name in a reviewed call, and the projectors' `fold/3` is
  the one place machinery takes it.
- **#14 A projection table is declared with `Oneiroi.Migration.projection/3`.**
  It adds the scope columns, enables and forces row-level security, and
  writes the one policy (`platform OR own-scope`, `USING` and
  `WITH CHECK`); a bare `create table` is what the `tables` check
  reports, and a raw `CREATE TABLE` is reported unless the table is one
  the kernel reserves (`projection_versions`).
- **#15 Events carry their actor and instant; a decision carries a note.**
  `use Oneiroi.Event` and `use Oneiroi.Command` make the fields enforced
  keys, and `Oneiroi.Commanded.Middleware.Actor` refuses a command whose
  actor is invalid, whose instant is missing, or whose note is blank on a
  decision, or whose bounded name (`bounds:`) is too long. An event's `version:` is listed in its system's `events/0`;
  a shape change is a new version with an upcaster, and the fixture log
  under `test/fixtures/sima_qian/` is the test that fails without one.
- **#16 The macro modules are leaves.** `Oneiroi.Event` is the macro and
  `Oneiroi.Event.Codec` the restoring; the router and projection macros
  name the application, the repo and the middleware as atoms built with
  `Module.concat/1`, and the Commanded application reads its event store
  from config. Each is what keeps a `use` line off the compile-connected
  graph the ratchet is armed against.
- **#17 Secrets at rest are AES-256-GCM under `APSU_VAULT_KEY`.**
  `Oneiroi.Apsu.Vault` over `:crypto`, with `Vault.Encrypted` as the
  Ecto type; the key is a declared secret with no default, recorded in
  `SETUP.md`'s manifest. The plan named `cloak_ecto`; it arrived with two
  open advisories and no fixed release, and the gate that refuses an
  advisory is the gate that chose this.
- **#18 The fake clock is per process and microsecond-precise.** A test
  moves its own clock with `Clock.Fake.advance/1`; every instant lands
  in a `:utc_datetime_usec` column, and a coarser instant is refused by
  Ecto rather than silently widened.

- **#19 The endpoint answers as `RENDER_EXTERNAL_URL`.** Render sets
  it on every web service, previews included, to the service's own
  origin; Apsu declares it `external: true` beside `DATABASE_URL`, casts
  it to the endpoint's `url:` at boot, and `OneiroiWeb.Plugs.Origin`
  compares a browser's `Origin` against the result. The test source
  sets it to a name that is not localhost, so the suite can tell the
  declared origin from the listener's.
- **#20 Oban's Lifeline rescues every queue's orphans after
  `APSU_LIFELINE_RESCUE_AFTER_MINUTES` (540).** A job still `executing`
  that long goes back to `available`, or to `discarded` when it has no
  attempt left. Time alone decides, so the bound sits above the longest
  legitimate job, a full regression run at the request timeout, and a
  test holds it above that product. A worker that must not run twice
  declares `max_attempts: 1` on `Oneiroi.Worker` (eunomia#30).
- **#21 A projector parks an event it cannot fold; it never stops the
  app.** `use Oneiroi.Projection` routes every handler error to
  `Oneiroi.Projection.failed/4`: a transient Postgres refusal or a lost
  connection is retried 3 times at 500 ms times the attempt, and
  anything else, or a transient one past its retries, is skipped,
  logged at error with the projector, the event's number, type and
  stream (never its data), and told as `[:oneiroi, :projection, :parked]`
  telemetry. The event stays in the store for a replay once the fold is
  fixed (conventions §6, 2026-11-03).
- **#22 Free text is `:text`; a bound belongs on the command.** The
  `free_text` check reads every migration from `20261103000010` on and
  reports an `add` or `modify` of `:string` (Ecto's `varchar(255)`)
  unless the name is an identifier by name or suffix. A name that should
  be short is bounded with `use Oneiroi.Command, bounds: [field: max]`,
  and the actor middleware refuses an overlong one as
  `<field>_too_long` at dispatch, before any event exists (conventions
  §6, §12).
- **#23 The ops read surface: the failures as facts, the heartbeats as absences.** (The witness, 2026-11-04: "we just need a formal, owned querying surface"; design/logging-and-alerting.md step 1, Lily's, built 2026-11-06.) `Oneiroi.Apsu.Ops` owns two tables in its own process. The failure ring is a logger handler at warning and above keeping the last `APSU_FAILURE_RING` (200) as facts: when, level, component, error kind, site and cause, trace id, and the message trimmed to 300 characters and scrubbed by `LogRedacting`'s patterns; in-process so it answers when the backends are down, and gone on a restart, which the logs outside keep. The beats record when each adapter last asked `/waiting`. `GET /v1/ops/failures` (a super admin's: platform-wide) reads the ring, narrowed by kind, site, component or trace id, beside the jobs Oban discarded in the last day (worker, when, the attempt, the last error scrubbed, never the arguments). `GET /v1/residents/:id/ops/heartbeats` (the witness's) lists what always happens for the resident, when it last did and how often it should, read where it is already recorded: the backup when a remote is set (26 hours), free time's last run (26 hours), rounds' last start when they are on (14 hours, a waking day's gap), each live adapter's last ask (a reader 30 minutes; a brain only while its runtime is open, so unbounded); `late` when past it or never seen. Neither returns a word of conversation. Steps 2 and 3 (metrics with four alerts, logs shipped off Render) wait on the witness's calls: where the backend lives, and where an alert lands.

## #10 Initial vs target

Initial (P0): the roster, the boot, the endpoint with `/health` and the
`/v1` router, the kernel above, Oban, the event store on Postgres in
every environment, the audit checks, JSON logs, the Dockerfile and
blueprint. Target: PromEx, the status page, the fleet pins checked
against the catalogue (spec §6.16).

## #11 Depends on

The substrate (`systems/daedalus.md`). Nothing else in this repo: it is
the bottom.
