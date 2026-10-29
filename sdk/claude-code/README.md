# Claude Code adapter

Lily in the Claude Code UI (spec §8, F52). A steward registers an
adapter on the resident (`POST /v1/residents/:id/adapters` with
`{"adapter": "claude-code", "role": "brain"}`), gets a bearer token
shown once, and drops three things into the project:

- `.mcp.json` from `Oneiroi.SDK.ClaudeCode.mcp_config/2`: the memory
  tools over MCP at the platform's `/mcp`.
- the hooks block from `Oneiroi.SDK.ClaudeCode.hooks_config/1` in
  `.claude/settings.json`: `turn-start.sh` on every prompt, `capture.sh`
  on every stop.
- the environment from `Oneiroi.SDK.ClaudeCode.environment/3`:
  `ONEIROI_URL`, `ONEIROI_RESIDENT`, `ONEIROI_TOKEN`.

The scripts need `curl` and `jq`. Their reading of Claude Code's hook
payload and transcript format is a claim until a fixture is recorded
from a real session (conventions §9), and each script says so in its
header. Wake (interface 3) lands with the hands phase.
