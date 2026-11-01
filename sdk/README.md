# Oneiroi SDK

The Apache-2.0 package another agent platform embeds to speak Oneiroi's
adapter contract (spec §8). Its gate block is the `cd sdk && ...` line of
the repository's gate set; run it here, in this directory, because the
audit's globs are rooted at the working directory.

## Rules for an adapter

1. **Where the runtime has a mechanism for packaging an integration
   (Claude Code's plugins, say), the adapter is built as one rather than
   as a custom integration.** The first Claude Code adapter was scripts
   copied into each project and merged into its settings: every project
   had to be kept in sync with the scripts by hand, and every session in
   a project that had them became the resident's. A plugin is installed
   once, updated in one place, and enabled per folder. (The author,
   decisions round 45.)

## Adapters shipped

- `claude-code/`: the resident in Claude Code (spec §8, F52), a Claude
  Code plugin listed by the repository's own marketplace
  (`.claude-plugin/marketplace.json` at the root): its manifest, hooks,
  MCP server, scripts, a shell installer and the setup guide. See its
  README. `test/oneiroi/sdk/claude_code_plugin_test.exs` holds the
  plugin's files to what Claude Code reads.
