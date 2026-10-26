# Oneiroi — repo specifics

What only this repo can say. The pipeline protocol (roles, states,
markers, mutex, file maps) is injected into every agent run from the
pipeline checkout and is not restated here; where that file and this
one disagree about protocol, that file wins.

## What this is

A hosted, multi-tenant platform for AI residents and their stewards.
Design source of truth: `design/oneiroi-spec.md` (cited as *spec §n*).
Build sequencing: `design/p0-plan.md`. Coding rules with their reasons:
`design/conventions.md` (*conventions §n*): read it before writing
code; every rule carries the failure it prevents. Architecture:
`systems/*.md`, one doc per system with a file map; the reason behind
each numbered rule is in the `.reasons.md` sibling.

## Toolchain

Pinned in `.tool-versions` (Erlang 27.3.4, Elixir 1.17.3-otp-27, Node
22); CI reads the same file strictly, and `mix.exs` floors match. The
pinned toolchain is the only supported one.

## Layout

- `lib/oneiroi/` — the core, one system per directory (spec §6), each a
  Boundary adopting `use Oneiroi.System`.
- `lib/oneiroi_web/` — the endpoint, router and JSON surface.
- `components/substrate/` — the platform substrate, lifted from Catapult
  (Apache-2.0): its own mix project with its own gate block. Citations of
  the form `v5 §n` and `ORC-n` inside it are Catapult's, kept as the
  provenance of each rule; `systems/substrate.md` says where they resolve.
- `sdk/` — the adapter SDK, its own mix project, Apache-2.0. Never copy
  core code into it; never add a copyleft dependency under it.
- `client/` — the React client on the Oneiroi design system
  (`client/src/tokens.json`), with Storybook. `vite build` writes to
  `priv/static/client`; the storybook export is served on previews.
- `design/` — spec, conventions, plan, decisions log.

## Verification (run all before claiming done)

The gate set is one block, identical here, in `.github/workflows/ci.yml`
and in `pipeline.config.json`'s `qualityGates`; `mix oneiroi.audit`'s
`gates` check fails on a difference. Each `cd` line is one gate: the
gate set is a property of a mix project, and the audit's globs are rooted
at the working directory, so each project runs its own block.

```oneiroi:gates
mix deps.get --check-locked          # lockfile integrity: a hard gate, never softened
mix deps.audit                       # hex.audit first (the supply gate), mix_audit second
mix format --check-formatted
mix credo --strict                   # disagreements are config changes in a reviewed commit, never inline disables
mix sobelow --exit --skip --ignore Config.HTTPS   # armed from day one; Config.HTTPS: Render terminates TLS, the probe is plain http
mix compile --warnings-as-errors     # the Boundary compiler is in the set
mix xref graph --format cycles --fail-above 0
mix xref graph --label compile-connected --fail-above 0   # the ratchet, armed at 0 while it is free
mix oneiroi.audit                    # the check registry (conventions §13); this project only, see below
mix test                             # no network
cd client && npm ci && npm run lint && npm run typecheck && npm test && npm run build-storybook
cd components/substrate && mix deps.get --check-locked && mix hex.audit && mix format --check-formatted && mix credo --strict && mix compile --warnings-as-errors && mix xref graph --format cycles --fail-above 0 && mix xref graph --label compile-connected --fail-above 0 && mix oneiroi.audit && mix test
cd sdk && mix deps.get --check-locked && mix hex.audit && mix format --check-formatted && mix credo --strict && mix compile --warnings-as-errors && mix xref graph --format cycles --fail-above 0 && mix xref graph --label compile-connected --fail-above 0 && mix oneiroi.audit && mix test
```

Each mix project runs its own `mix oneiroi.audit` inside its own block,
after its own `deps.get`: the audit's globs are rooted at the working
directory, and a project whose deps are unresolved exits 1 rather than
skipping. `mix oneiroi.audit.all` at the root runs all three once each
project's deps are fetched, and is the local shortcut, not a gate line.

The ratchet's number lives only in `pipeline.config.json` and `ci.yml`,
both author-owned, so a ticket cannot raise it. Tests: no network, ever;
`:live` is a cadence, never a gate. CI runs as an ordinary user; a root
pass can hide a harness that only works as root, so run the block that
way before trusting a local green.

## Load-bearing invariants (the ones agents trip on)

- Every system adopts `use Oneiroi.System, slug: :<name>` and declares its
  claims; the composer fails the boot **and** the audit on a collision.
  Root artifacts (the supervisor, the router) are composed from those
  declarations, never hand-edited.
- Public functions on a system's boundary use `defexport`.
- No `DateTime.utc_now` in domain code (inject `Oneiroi.Clock`); no bare
  `name: __MODULE__` (register via `processes/0`); no unwrapped
  `Oneiroi.Config.Secret` inside a `Logger` call. The audit parses rather
  than greps. The escape is a **comment**, `# oneiroi:allow <check>`, on
  the offending line or the comment line directly above it, and a tag
  covering no violation is itself reported.
- A setting is a `config/0` declaration with a `usage:` line, a `tag:`
  (`:bound` or `:measured`) when numeric, and a default unless it is a
  secret, an external name or `required: false`. A required value this
  codebase invented is recorded in `SETUP.md`'s `oneiroi:required-env`
  block, or the audit says so.
- `@tag :skip` needs a ticket key: `@tag skip: "ORC-n reason"`.
- The gate block above is the gate block; editing one copy is an audit
  failure until all three agree.
- Every table carries `resident_id` or `account_id` and a row-level
  policy; the application role cannot bypass RLS (from P0.2).
- Events are immutable contracts: a change is a new version with an
  upcaster; every event carries its actor and, for model output, the
  model slug; every decision event carries `note` (from P0.2).
- The core makes model calls only through the provider port, metered by
  the ledger (from P1).

## Where things actually run

- **Agent runs have no BEAM**; the gates run in `ci.yml` on the PR.
- **The pipeline audit only runs on ticket branches** (a key in the branch
  name and `PIPELINE_REPO_TOKEN`); a clean run on an author branch is not
  evidence it passed.
- **A stale `_build` fails `--warnings-as-errors` for a lie.** Before
  believing such a failure, `mix compile --force`.
