defmodule Oneiroi.SDK.ClaudeCode do
  @moduledoc """
  The Claude Code adapter (spec §8, F52: Lily in the Claude Code UI):
  the configuration a steward drops into a project so a Claude Code
  session is the resident's brain. Three pieces, one per interface of
  the adapter contract.

  1. Memory tools over MCP: `.mcp.json` pointing at the platform's `/mcp`
     with the adapter's bearer token.
  2. Turn capture and context: Claude Code hooks. `UserPromptSubmit`
     runs `turn-start.sh`, which reports the turn and prints the context
     index for Claude Code to inject; `Stop` runs `capture.sh`, which
     reads the session transcript and posts the turn, idempotent on
     (session, timestamp, hash), spooling on a failure for the next stop.
  3. Wake: the remote trigger lands with the hands phase (P5).

  The scripts live beside this module under `sdk/claude-code/`; this
  module renders the two JSON files so a steward never hand-edits a
  hook block. The hook payload shapes are Claude Code's, and the
  fixtures the scripts are tested against must be recorded from a real
  session (conventions §9); until one is recorded here, the scripts are
  a claim about Claude Code and say so in their header.
  """

  @scripts "sdk/claude-code"

  @doc "The `.mcp.json` for a project: the platform's MCP server over streamable HTTP with the adapter's token."
  @spec mcp_config(String.t(), String.t()) :: map()
  def mcp_config(base_url, token) when is_binary(base_url) and is_binary(token) do
    %{
      "mcpServers" => %{
        "oneiroi" => %{
          "type" => "http",
          "url" => String.trim_trailing(base_url, "/") <> "/mcp",
          "headers" => %{"Authorization" => "Bearer " <> token}
        }
      }
    }
  end

  @doc """
  The hooks block for `.claude/settings.json`: turn-start on every prompt,
  capture on every stop. `scripts_dir` is where the two scripts live;
  the platform URL, the resident id and the token reach the scripts
  through the environment named in their headers.
  """
  @spec hooks_config(String.t()) :: map()
  def hooks_config(scripts_dir \\ @scripts) when is_binary(scripts_dir) do
    hook = fn name -> %{"type" => "command", "command" => Path.join(scripts_dir, name)} end

    %{
      "hooks" => %{
        "UserPromptSubmit" => [%{"hooks" => [hook.("turn-start.sh")]}],
        "Stop" => [%{"hooks" => [hook.("capture.sh")]}]
      }
    }
  end

  @doc "The environment the scripts read, with the values a steward fills in."
  @spec environment(String.t(), String.t(), String.t()) :: map()
  def environment(base_url, resident_id, token) do
    %{
      "ONEIROI_URL" => base_url,
      "ONEIROI_RESIDENT" => resident_id,
      "ONEIROI_TOKEN" => token
    }
  end
end
