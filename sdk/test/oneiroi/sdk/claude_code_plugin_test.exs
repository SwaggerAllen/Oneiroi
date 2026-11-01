defmodule Oneiroi.SDK.ClaudeCodePluginTest do
  @moduledoc """
  The Claude Code plugin under `sdk/claude-code/` as Claude Code reads it
  (its plugin manifest reference): the manifest's options and default,
  the hooks file naming scripts that exist, the MCP server reading its
  token from the options, the repository's marketplace listing it, and
  the installer handing the token to Claude Code on stdin alone. JSON is
  read with jq, as the hooks read it, so the package needs no JSON
  library. The hooks themselves run against the platform's real
  endpoint in the core's suite (`OneiroiWeb.ClaudeCodeHooksTest`).
  """
  use ExUnit.Case, async: true
  import Bitwise

  @plugin Path.expand("../../../claude-code", __DIR__)
  @repo Path.expand("../../../..", __DIR__)
  @token "tok-NEVER-ON-A-COMMAND-LINE-123"

  defp jq(filter, file, args \\ []) do
    {out, 0} = System.cmd("jq", ["-c"] ++ args ++ [filter, file])
    String.trim(out)
  end

  test "the manifest is the oneiroi plugin, off until a project enables it, asking for the URL, the resident and a masked token" do
    manifest = Path.join(@plugin, ".claude-plugin/plugin.json")
    assert jq(".name", manifest) == ~s("oneiroi")
    assert jq(".defaultEnabled", manifest) == "false"
    assert jq(".userConfig | keys", manifest) == ~s(["record_fixtures","resident","token","url"])
    assert jq(".userConfig.token.sensitive", manifest) == "true"

    for key <- ~w(url resident token),
        do: assert(jq(".userConfig.#{key}.required", manifest) == "true", key)

    assert jq(".userConfig.url.default", manifest) == ~s("https://oneiroi.onrender.com")
  end

  test "every hook names a script that exists and runs, and the SessionStart hooks are the prefix's parts, numbered of the whole" do
    hooks = Path.join(@plugin, "hooks/hooks.json")

    commands =
      ~S<.hooks | to_entries[] | .key as $k | .value[] | .hooks[] | "\($k)\t\(.command)">
      |> jq(hooks, ["-r"])
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, "\t"))

    for [_event, command] <- commands do
      [_, script] = Regex.run(~r/^"\$\{CLAUDE_PLUGIN_ROOT\}\/([^"]+)"/, command)
      {:ok, %{mode: mode}} = File.stat(Path.join(@plugin, script))
      assert (mode &&& 0o100) != 0, "#{script} is not executable"
    end

    starts = for ["SessionStart", c] <- commands, do: c
    n = length(starts)
    assert n > 1

    assert starts ==
             Enum.map(1..n, &~s("${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh" #{&1} #{n}))

    assert Enum.sort(for [e, _] <- commands, uniq: true, do: e) ==
             ["SessionStart", "Stop", "UserPromptSubmit"]
  end

  test "the memory tools' server takes the URL and the token from the options, never a literal" do
    mcp = Path.join(@plugin, ".mcp.json")
    assert jq(".mcpServers.oneiroi.url", mcp) == ~s("${user_config.url}/mcp")

    assert jq(~S<.mcpServers.oneiroi.headers.Authorization>, mcp) ==
             ~s("Bearer ${user_config.token}")
  end

  test "the repository's marketplace lists the plugin from this directory" do
    marketplace = Path.join(@repo, ".claude-plugin/marketplace.json")
    assert jq(".name", marketplace) == ~s("oneiroi")

    assert jq(~S<.plugins[] | select(.name == "oneiroi") | .source>, marketplace) ==
             ~s("./sdk/claude-code")
  end

  test "nothing the plugin says names a resident of its own" do
    files =
      [".claude-plugin/plugin.json", "hooks/hooks.json", ".mcp.json"] ++
        (@plugin
         |> Path.join("scripts/*.sh")
         |> Path.wildcard()
         |> Enum.map(&Path.relative_to(&1, @plugin)))

    for file <- files, do: refute(File.read!(Path.join(@plugin, file)) =~ ~r/lily/i, file)
  end

  # `claude` and `jq` as the installer finds them on PATH, each recording
  # its arguments (what the process list shows) and `claude` its stdin.
  defp shims(root) do
    bin = Path.join(root, "bin")
    File.mkdir_p!(bin)

    File.write!(Path.join(bin, "claude"), """
    #!/usr/bin/env bash
    printf 'claude %s\\n' "$*" >> "#{root}/argv.log"
    printf 'cwd %s\\n' "$PWD" >> "#{root}/argv.log"
    case "$*" in
      *--values-stdin*) cat > "#{root}/stdin.json" ;;
      "plugin list --json") printf '[{"id":"oneiroi@oneiroi","enabled":true}]' ;;
    esac
    exit 0
    """)

    File.write!(Path.join(bin, "jq"), """
    #!/usr/bin/env bash
    printf 'jq %s\\n' "$*" >> "#{root}/argv.log"
    exec #{System.find_executable("jq")} "$@"
    """)

    for name <- ~w(claude jq), do: File.chmod!(Path.join(bin, name), 0o755)
    bin
  end

  test "the installer installs at local scope in the folder, enables it there, and hands the token over on stdin alone" do
    root = Path.join(System.tmp_dir!(), "oneiroi-install-#{System.unique_integer([:positive])}")
    project = Path.join(root, "project")
    File.mkdir_p!(project)
    on_exit(fn -> File.rm_rf!(root) end)
    bin = shims(root)

    {out, 0} =
      System.cmd(
        "bash",
        [Path.join(@plugin, "install.sh"), project, "res-1", "https://o.example/"],
        env: [{"PATH", bin <> ":" <> System.get_env("PATH")}, {"ONEIROI_TOKEN", @token}],
        stderr_to_stdout: true
      )

    argv = File.read!(Path.join(root, "argv.log"))
    refute argv =~ @token
    refute out =~ @token

    claude =
      for "claude " <> line <- String.split(argv, "\n"), do: line

    assert claude == [
             "plugin install oneiroi --marketplace #{@repo} --scope local --config url=https://o.example --config resident=res-1",
             "plugin enable oneiroi@oneiroi --scope local",
             "plugin list --json",
             "plugin configure oneiroi@oneiroi --values-stdin"
           ]

    assert Enum.all?(for("cwd " <> dir <- String.split(argv, "\n"), do: dir), &(&1 == project))

    assert File.read!(Path.join(root, "stdin.json")) ==
             ~s({"url":"https://o.example","resident":"res-1","token":"#{@token}"}\n)

    assert out =~ ~s(cd "#{project}" && claude remote-control --spawn session)
  end
end
