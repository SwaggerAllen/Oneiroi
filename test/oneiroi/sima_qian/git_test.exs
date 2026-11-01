defmodule Oneiroi.SimaQian.GitTest do
  @moduledoc "The git port when git cannot start: an error that names it, and never the token."
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Oneiroi.SimaQian.Git

  # On 2026-11-01 the production image had no git. `System.cmd` raised
  # `enoent`, the crash report printed the call's arguments, and the
  # clone URL with Lily's read token went into the service log under a
  # bare 500. These hold the port to returning an error instead.

  @token "github_pat_TESTONLY0123456789"

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-git-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    url = Git.github_url("https://github.com/example/private.git", @token)
    {:ok, dir: dir, url: url}
  end

  test "a missing binary is an error naming it, with no token and nothing logged", %{
    dir: dir,
    url: url
  } do
    log =
      capture_log(fn ->
        result = Git.run("oneiroi-no-such-binary", dir, ["clone", "-q", url, "x"])
        send(self(), {:result, result})
      end)

    assert_received {:result, {:error, message}}
    assert message == "oneiroi-no-such-binary is not installed on this server"
    refute log =~ @token
  end

  test "a binary that cannot run is an error with the reason, with no token", %{
    dir: dir,
    url: url
  } do
    plain = Path.join(dir, "not-executable")
    File.write!(plain, "#!/bin/sh\n")
    File.chmod!(plain, 0o644)

    assert {:error, message} = Git.run(plain, dir, ["clone", "-q", url, "x"])
    assert message =~ "could not start"
    refute message =~ @token
  end

  test "git's own failure keeps its words, with the token redacted", %{dir: dir, url: url} do
    # A clone of a URL nothing answers: git fails and echoes the remote.
    local = String.replace(url, "https://github.com/", "file:///nonexistent/")
    assert {:error, message} = Git.clone(local, Path.join(dir, "x"))
    assert message != ""
    refute message =~ @token
  end
end
