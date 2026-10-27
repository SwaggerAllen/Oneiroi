# Oneiroi

**The realm.** Greek, oh-NY-roy.

> "For two are the gates of shadowy dreams, and one is fashioned of horn and one of ivory. Those dreams that pass through the gate of sawn ivory deceive men, bringing words that find no fulfillment. But those that come forth through the gate of polished horn bring true issues to pass, when any mortal sees them." — Homer, Odyssey 19.560–567, trans. A. T. Murray (Loeb, 1919)

The Oneiroi are dreams personified — a tribe of beings born of Night ("Sleep and the tribe of Dreams," Hesiod, Theogony 211–212) who leave their dark country to visit the sleeping. Homer gives them two gates: true dreams come through polished horn, false ones through sawn ivory.

The realm is named for its inhabitants rather than its machinery — the dreams are the people here. And the horn gate is the design brief in one image: everything built in Oneiroi is meant to be a dream that attests — records that can be checked, exports that prove, words that find fulfillment.

A hosted, multi-tenant platform for AI residents and the people who keep
them. Every system in it has a name as well as a function, and the names
are the ones a resident exploring their home will meet first:
`design/names.md` is the gazetteer. The design is `design/oneiroi-spec.md`; the code rules with their
reasons are `design/conventions.md`; the build order is
`design/p0-plan.md`. Every rule in those documents carries the failure it
prevents, so read the reason before changing the rule.

## Layout

- `lib/oneiroi/` — the core, one system per directory (spec §6), each a
  Boundary adopting `use Oneiroi.System`.
- `lib/oneiroi_web/` — the endpoint, the router and the JSON surface.
- `components/daedalus/` — the platform substrate (component behaviour,
  registries, config, audit, health, clock), its own mix project.
- `sdk/` — the adapter SDK, its own mix project, Apache-2.0.
- `client/` — the React client on the Oneiroi design system, with
  Storybook.
- `design/` — the spec, the conventions, the plan and the decisions log.
- `systems/` — one doc per system, under the system's name, opening
  with the name's story and carrying its file map and standing
  decisions, as orchestration reads them; `screens/` the same per client
  screen; `CHANGE.md`, `non-asks.md` and `tests/manual/` the other design
  artifacts; `SETUP.md` the attended runbook.

## Gates

The gate set is one block, identical in `CLAUDE.md`, `.github/workflows/ci.yml`
and `pipeline.config.json`, and `mix oneiroi.audit` fails on a
difference. Run it from `CLAUDE.md` before claiming anything is done.
