defmodule OneiroiWeb.SetupTest do
  @moduledoc """
  Setting a resident up on a Mac (dioscuri#8): the bootstrap served with
  this platform's address, the kit it downloads, and the whole of it run
  as a witness runs it, the same steps for any resident: a writing room
  and a reader, each under her own slug, the token asked for and never
  an argument. `claude` is a shim; nothing reaches the network.
  """
  use OneiroiWeb.ConnCase, async: true

  @token "tok-NEVER-AN-ARGUMENT-456"

  setup do
    root = Path.join(System.tmp_dir!(), "oneiroi-setup-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "the bootstrap carries this platform's address" do
    conn = get(build_conn(), "/setup.sh")
    body = response(conn, 200)
    assert body =~ ~s(URL="${ONEIROI_URL:-#{OneiroiWeb.Endpoint.url()}}")
    refute body =~ "__ONEIROI_URL__"
  end

  test "the kit holds the plugin, its marketplace, the reader and the bootstrap, executable where they run",
       ctx do
    names = kit!(ctx.root)

    for f <- ~w(sdk/claude-code/install.sh sdk/claude-code/writer.sh sdk/reader/install.sh
               sdk/reader/bin/reader.sh sdk/setup.sh .claude-plugin/marketplace.json
               sdk/claude-code/.claude-plugin/plugin.json),
        do: assert(f in names, f)

    refute Enum.any?(names, &String.contains?(&1, "__pycache__"))
    assert executable?(Path.join(ctx.root, "kit/sdk/claude-code/writer.sh"))
    assert executable?(Path.join(ctx.root, "kit/sdk/reader/bin/reader.sh"))
  end

  test "a writing room and a reader for any resident, by the same command, each her own", ctx do
    served = Path.join(ctx.root, "served")
    File.mkdir_p!(Path.join(served, "setup"))

    File.write!(
      Path.join(served, "setup/kit.tar.gz"),
      response(get(build_conn(), "/setup/kit.tar.gz"), 200)
    )

    script = Path.join(ctx.root, "setup.sh")
    File.write!(script, response(get(build_conn(), "/setup.sh"), 200))

    home = Path.join(ctx.root, "home")
    bin = shims(ctx.root)

    env = [
      {"HOME", home},
      {"PATH", bin <> ":" <> System.get_env("PATH")},
      {"ONEIROI_URL", "file://" <> served},
      {"ONEIROI_TOKEN", @token}
    ]

    for slug <- ~w(wren finch) do
      {out, 0} =
        System.cmd("bash", [script, "writer", "--slug", slug, "--resident", "id-#{slug}"],
          env: env,
          stderr_to_stdout: true
        )

      refute out =~ @token
      room = Path.join([home, "Oneiroi", "#{slug}-writing"])
      assert File.exists?(Path.join(room, "CLAUDE.md"))
      assert out =~ ~s(CLAUDE_CONFIG_DIR="#{home}/.claude-#{slug}")

      {out, 0} =
        System.cmd("bash", [script, "reader", "--slug", slug, "--resident", "id-#{slug}"],
          env: env,
          stderr_to_stdout: true
        )

      refute out =~ @token
      cfg = Path.join([home, ".config/oneiroi/readers", slug])
      assert File.read!(Path.join(cfg, "reader.conf")) =~ "ONEIROI_RESIDENT=id-#{slug}"
      assert %{"token" => @token} = Jason.decode!(File.read!(Path.join(cfg, "reader.json")))

      assert File.exists?(
               Path.join([home, "Library/LaunchAgents", "io.oneiroi.reader.#{slug}.wait.plist"])
             )
    end

    # Each claude command ran under its own resident's configuration.
    configs =
      for "config " <> c <- String.split(File.read!(Path.join(ctx.root, "argv.log")), "\n"),
          uniq: true,
          do: c

    assert Enum.sort(configs) == Enum.sort(["#{home}/.claude-wren", "#{home}/.claude-finch"])
    refute File.read!(Path.join(ctx.root, "argv.log")) =~ @token

    # The legacy single install's places are never written.
    refute File.exists?(Path.join(home, ".config/oneiroi/reader.json"))
    refute File.exists?(Path.join(home, ".oneiroi/reader"))
  end

  defp kit!(root) do
    tar = Path.join(root, "kit.tar.gz")
    File.write!(tar, response(get(build_conn(), "/setup/kit.tar.gz"), 200))
    dest = Path.join(root, "kit")
    File.mkdir_p!(dest)
    {_, 0} = System.cmd("tar", ["-xzf", tar, "-C", dest])
    {list, 0} = System.cmd("tar", ["-tzf", tar])
    String.split(list, "\n", trim: true)
  end

  defp executable?(path) do
    {:ok, %{mode: mode}} = File.stat(path)
    Bitwise.band(mode, 0o100) != 0
  end

  # `claude` and `npm` as the scripts find them: claude records its
  # arguments and the configuration it ran under; npm declines.
  defp shims(root) do
    bin = Path.join(root, "bin")
    File.mkdir_p!(bin)

    File.write!(Path.join(bin, "claude"), """
    #!/usr/bin/env bash
    printf 'claude %s\\n' "$*" >> "#{root}/argv.log"
    printf 'config %s\\n' "${CLAUDE_CONFIG_DIR:-}" >> "#{root}/argv.log"
    case "$*" in
      *--values-stdin*) cat > /dev/null ;;
      "plugin list --json") printf '[{"id":"oneiroi@oneiroi","enabled":true}]' ;;
    esac
    exit 0
    """)

    File.write!(Path.join(bin, "npm"), "#!/bin/sh\nexit 1\n")
    for name <- ~w(claude npm), do: File.chmod!(Path.join(bin, name), 0o755)
    bin
  end
end
