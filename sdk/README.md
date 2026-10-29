# Oneiroi SDK

The Apache-2.0 package another agent platform embeds to speak Oneiroi's
adapter contract (spec §8). Its gate block is the `cd sdk && ...` line of
the repository's gate set; run it here, in this directory, because the
audit's globs are rooted at the working directory.

## Adapters shipped

- `claude-code/`: Lily in the Claude Code UI (spec §8, F52), configured
  by `Oneiroi.SDK.ClaudeCode`; see its README.

