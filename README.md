# Oneiroi

A hosted, multi-tenant platform for AI residents and the people who keep
them. The design is `design/oneiroi-spec.md`; the code rules with their
reasons are `design/conventions.md`; the build order is
`design/p0-plan.md`. Every rule in those documents carries the failure it
prevents, so read the reason before changing the rule.

## Layout

- `lib/oneiroi/` — the core, one system per directory (spec §6), each a
  Boundary adopting `use Oneiroi.System`.
- `lib/oneiroi_web/` — the endpoint, the router and the JSON surface.
- `components/substrate/` — the platform substrate (component behaviour,
  registries, config, audit, health, clock), its own mix project.
- `sdk/` — the adapter SDK, its own mix project, Apache-2.0.
- `client/` — the React client on the Oneiroi design system, with
  Storybook.
- `design/` — the spec, the conventions, the plan and the decisions log.
- `systems/` — one doc per system with its file map and standing
  decisions, as orchestration reads them.

## Gates

The gate set is one block, identical in `CLAUDE.md`, `.github/workflows/ci.yml`
and `pipeline.config.json`, and `mix oneiroi.audit` fails on a
difference. Run it from `CLAUDE.md` before claiming anything is done.
