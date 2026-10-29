defmodule Oneiroi.SDK.ClaudeCodeTest do
  use ExUnit.Case, async: true
  import Bitwise

  alias Oneiroi.SDK.ClaudeCode

  test "the MCP config points at /mcp with the bearer token" do
    assert %{
             "mcpServers" => %{
               "oneiroi" => %{
                 "type" => "http",
                 "url" => "https://o.example/mcp",
                 "headers" => %{"Authorization" => "Bearer t"}
               }
             }
           } = ClaudeCode.mcp_config("https://o.example/", "t")
  end

  test "the hooks block runs turn-start on every prompt and capture on every stop" do
    assert %{
             "hooks" => %{
               "UserPromptSubmit" => [
                 %{"hooks" => [%{"command" => "/x/turn-start.sh", "type" => "command"}]}
               ],
               "Stop" => [%{"hooks" => [%{"command" => "/x/capture.sh"}]}]
             }
           } = ClaudeCode.hooks_config("/x")
  end

  test "the scripts the hooks name exist and are executable" do
    for name <- ["turn-start.sh", "capture.sh"] do
      path = Path.join([__DIR__, "../../../claude-code", name])
      assert File.exists?(path), name
      {:ok, %{mode: mode}} = File.stat(path)
      assert (mode &&& 0o100) != 0, "#{name} is not executable"
    end
  end

  test "the environment names the three values the scripts read" do
    assert %{"ONEIROI_URL" => "u", "ONEIROI_RESIDENT" => "r", "ONEIROI_TOKEN" => "t"} =
             ClaudeCode.environment("u", "r", "t")
  end
end
