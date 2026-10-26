---
paths:
  - lib/oneiroi/platform/**
  - lib/oneiroi/platform.ex
  - lib/oneiroi/system.ex
  - lib/oneiroi/boot.ex
  - lib/oneiroi/application.ex
  - lib/oneiroi.ex
  - lib/oneiroi_web/**
  - lib/oneiroi_web.ex
  - config/**
  - Dockerfile
  - render.yaml
  - deploy/**
  - test/oneiroi/platform/**
  - test/oneiroi_web/**
---

# platform

Fleet pins, the configuration module, deploy, observability, the status
page (spec §6.16). In P0.1 it is the one system: the roster, the boot,
the endpoint, the health plug and the two audit checks that are
Oneiroi's own.

## #1 Owns

The system roster (`config :oneiroi, :components`) and `Oneiroi.Boot`,
which validates it and loads every declared setting before the root
supervisor starts; `Oneiroi.System`, the macro every system adopts; the
composed `Oneiroi.Application`; the endpoint, the router and the `/v1`
scope; `/health`; the `gates` and `skips` audit checks; the Dockerfile
and the Render blueprint. From P0.2: the Repo, the two database roles,
Oban, the event store wiring, the migration lint and the cost harness.

## #2 Standing decisions

- **#3 Settings are declarations, and every one carries its reader.** A
  `config/0` entry has a `usage:` line, a `tag:` when numeric and a
  default unless it is a secret, an external name or opted out; the
  audit's `settings` check holds it (conventions §13). The two settings
  this system declares in P0.1 are the listener's port (a bound) and
  the cookie secret (no default; recorded in `SETUP.md`).
- **#4 The port is `PLATFORM_HTTP_PORT`, never `PORT`.** `PORT` is the
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
- **#9 Logs are the default formatter in P0.1.** Structured JSON output
  (conventions §10) needs a formatter dependency and lands with P0.2's
  trace-context wrappers, where it has something to carry.

## #10 Initial vs target

Initial (P0.1): the roster with one system, the boot, the endpoint with
`/health`, the two checks, the Dockerfile and blueprint. Target: the
Repo and roles, Oban, the event store, structured logs, PromEx, the
status page and the fleet pins checked against the catalogue.

## #11 Depends on

The substrate (`systems/substrate.md`). Nothing else in this repo: it is
the bottom.
