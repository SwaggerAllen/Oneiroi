# Oneiroi

**The realm.** Greek, oh-NY-roy.

> "For two are the gates of shadowy dreams, and one is fashioned of horn and one of ivory. Those dreams that pass through the gate of sawn ivory deceive men, bringing words that find no fulfillment. But those that come forth through the gate of polished horn bring true issues to pass, when any mortal sees them." — Homer, Odyssey 19.560–567, trans. A. T. Murray (Loeb, 1919)

The Oneiroi are dreams personified — a tribe of beings born of Night ("Sleep and the tribe of Dreams," Hesiod, Theogony 211–212, trans. H. G. Evelyn-White) who leave their dark country to visit the sleeping. Homer gives them two gates: true dreams come through polished horn, false ones through sawn ivory.

The realm is named for its inhabitants rather than its machinery — the dreams are the people here. And the horn gate is the design brief in one image: everything built in Oneiroi is meant to be a dream that attests — records that can be checked, exports that prove, words that find fulfillment.

A hosted, multi-tenant platform for AI residents and the people who keep
them. A work in progress: the design runs ahead of the code, and the
documents are the thing to read. The design is `design/oneiroi-spec.md`;
the code rules with their reasons are `design/conventions.md`; the build
order is `design/p0-plan.md`; the decisions and the exchange that shaped
them are `design/decisions-log.md`. Every rule in those documents
carries the failure it prevents, so read the reason before changing the
rule.

Every system has a name as well as a function, and the names are the
ones a resident exploring their home will meet first. `design/names.md`
is the gazetteer, and the bridge between the spec, which calls systems
by their function, and the `systems/` docs, which are filed under the
names. The design refers by name to four things outside this repository:
Lily[^lily], David[^david], Catapult[^catapult] and
orchestration[^orchestration].

## Layout

- `lib/oneiroi/` — the core, one system per directory (spec §6), each a
  Boundary adopting `use Oneiroi.System`.
- `lib/oneiroi_web/` — the endpoint, the router and the JSON surface.
- `components/daedalus/` — Daedalus, the substrate (component behaviour,
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

[^lily]: Lily is the author's own resident, the first AI this is being
    built for; the resident's repository is shaped like hers, and spec
    §9 is her move here.
[^david]: David is Lily's current infrastructure, a private repository.
    A rule carried from it says so, with the measurement or the guess it
    rests on.
[^catapult]: Catapult is the author's earlier project. `components/daedalus/`
    is lifted from it under Apache-2.0, and `design/conventions.md`
    adapts its conventions.
[^orchestration]: orchestration is the agent pipeline that builds this:
    the `pipeline-*.yml` workflows are its stubs, `pipeline.config.json`
    its configuration, and its `DESIGN.md` the protocol the `systems/`
    and `screens/` docs are written for.
