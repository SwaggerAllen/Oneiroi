# Unowned paths, deliberately

The protocol's rule: every path is either in exactly one system's file
map, or it is unowned on purpose and listed here. For unowned paths,
git's textual conflict detection is the mutex; nothing else arbitrates.

- **Repo-root prose and build files**: `README.md`, `SETUP.md`,
  `LICENSING.md`, `LICENSE`, `CLAUDE.md`, `mix.exs`, `mix.lock`,
  `.formatter.exs`, `.credo.exs`, `.tool-versions`, `.gitignore`,
  `pipeline.config.json`. Shared by construction: a system claiming any
  of these would take a mutex over every ticket that adds a dependency
  or touches the toolchain.
- **`.github/workflows/**`**: author-owned by GitHub's own rule, since an
  agent's push token carries no `workflow` scope and the push is
  rejected. The twelve pipeline stubs are copied from orchestration's
  `examples/stubs` and kept in step by hand.
- **`design/**`**: the spec, the conventions, the plan, the decisions
  log and the critiques. Governed by review of the documents themselves;
  no system has standing to own the record of decisions that shaped all
  of them.
- **`systems/*.md`** (this file and each doc's `.reasons.md` sibling),
  **`screens/**`**, **`storybook/**`**, **`CHANGE.md`**, **`non-asks.md`**
  and **`tests/manual/**`**: design-owned via `designOwnedPaths`; the
  owner is the design process, not a system.
- **`components/substrate/**`** and **`sdk/**`**: each its own mix
  project with its own gate block, owned by `systems/substrate.md` and,
  for the SDK, by the adapter contract spec §8 once P1 writes it; listed
  here because the SDK has no system doc yet.
- **`priv/static/client/**`**: the client's build output, written by
  `vite build` and never by hand; the client system owns the source.

Everything else in the tree belongs to a file map. A new unowned path is
a decision: it gets an entry and a reason here, in the same change that
creates it.
