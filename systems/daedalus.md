---
paths:
  - components/daedalus/**
---

# daedalus

**The substrate.** Greek, DED-uh-lus.

> "a dancing-floor like unto that which in wide Cnosus Daedalus fashioned of old for fair-tressed Ariadne." — Homer, Iliad 18.591–592, trans. A. T. Murray (Loeb, 1919)

Daedalus is the craftsman of Greek myth: the architect of the labyrinth, the first maker of moving figures, the man who built wherever he landed, exiled from Athens, building on Crete, fleeing to Sicily. The thread trick Ariadne gave Theseus was his (Ariadne's own name is already in the house, under Seshat); his son Icarus flew on his wings and fell.

The substrate, the component machinery lifted from Catapult, is named for the craftsman who came from elsewhere and built the house everything else lives in. The name keeps the caution with the craft: the labyrinth was built to hide something, and the wings were built too well for the one who wore them.

The platform substrate: the component behaviour and its registry roster,
the composer, the configuration layer, the boundary-export macro, the
audit task and its check registry, health, the injected clock, the
seeds runner. Its own mix project, Apache-2.0, consumed by the core and
by the SDK as a path dependency.

## #1 Owns

Everything under `components/daedalus/`. In the spec's vocabulary a
"component" here is a system (spec §6); `Oneiroi.System` is where the
two words meet.

## #2 Standing decisions

- **#3 Lifted from Catapult as a copy, never as a dependency.** Taken
  from `SwaggerAllen/catapult` at commit `4b72600da3c3`, renamed to
  the `Oneiroi` namespace, and Oneiroi's code from that commit on: no
  package, no git reference, no upstream remote. A later session may
  diff against that commit by choice; nothing obliges one to
  (design/p0-plan.md).
- **#4 The provenance citations stay.** `v5 §n` is Catapult's design
  document and `ORC-n` its tickets; both are cited inside Daedalus
  as the measurement behind a rule, and neither resolves in this tree.
  `pipeline.config.json` says so under `citationShorthands`, so a later
  pass does not invent a path. Prose that names Catapult as the product
  (a "generated project", `bundles/default`) describes where the code
  came from and is trimmed only where it would mislead about this tree.
- **#5 The word stays "component".** Renaming it to "system" throughout
  would touch every module and test for a vocabulary gain alone, and
  `Oneiroi.System` as a namespace would shadow nothing but would make
  every `alias` of it a hazard beside Elixir's own `System`.
- **#6 Oneiroi's additions are two config opts and one check.** `usage:`
  and `tag:` on a declaration (typed by the config layer), and
  `Oneiroi.Audit.Declarations.settings/2`, which judges only the tree
  that declares (conventions §13). Everything else is Catapult's
  substrate as it was, with its own tests, which are the probes already
  run against each guard.
- **#7 The task is layout-ignorant and the invoker lives in the root.**
  `mix oneiroi.audit`'s globs are rooted at the working directory; `mix
  oneiroi.audit.all` in the root `mix.exs` is what knows there are three
  projects, and it exits 1 rather than skipping one whose deps are
  unresolved.
- **#8 Checks that are Oneiroi's own are registered through
  `policies/0` by Apsu, never added to Daedalus's
  platform checks.** The substrate ships into the SDK, which other
  agent platforms embed; a check that is this repository's policy, in a
  package that ships into trees we do not own, is the allowlist mistake
  the license check was designed against.

## #9 Initial vs target

Initial: Daedalus as lifted plus #6. Target: the ES property
templates as a macro once the event spine lands (P0.2), and the
`model_port` and `prompts` checks registered by the systems that own the
port and the prompt files (P1).

## #10 Depends on

Nothing in this repo. `plug`, `telemetry` and `jason` as library deps.
