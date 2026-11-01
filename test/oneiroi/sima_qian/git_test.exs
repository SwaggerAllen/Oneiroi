defmodule Oneiroi.SimaQian.GitTest do
  @moduledoc "The git port when git cannot start: an error that names it, and never the token."
  use ExUnit.Case, async: true

  import Bitwise
  import ExUnit.CaptureLog

  alias Oneiroi.Config.Secret
  alias Oneiroi.SimaQian.Error
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
    remote = Git.github_url("https://github.com/example/private.git", @token)
    {:ok, dir: dir, remote: remote, url: Secret.unwrap(remote)}
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

    assert_received {:result, {:error, %Error{kind: :sima_qian_git_unstarted} = error}}
    assert error.site == :sima_qian_git_run_unstarted
    assert error.details == [binary: "oneiroi-no-such-binary", reason: :enoent]
    refute inspect(error) =~ @token
    refute log =~ @token
  end

  test "a binary that cannot run is an error with the reason, with no token", %{
    dir: dir,
    url: url
  } do
    plain = Path.join(dir, "not-executable")
    File.write!(plain, "#!/bin/sh\n")
    File.chmod!(plain, 0o644)

    assert {:error, %Error{kind: :sima_qian_git_unstarted} = error} =
             Git.run(plain, dir, ["clone", "-q", url, "x"])

    assert error.details == [binary: plain, reason: :eacces]
    refute inspect(error) =~ @token
  end

  test "git's own failure keeps its words, with the token redacted", %{dir: dir} do
    # A remote nothing answers on: git fails and names the remote.
    remote = Secret.wrap("https://x-access-token:#{@token}@127.0.0.1:9/x.git")

    assert {:error, %Error{kind: :sima_qian_git_failed, site: :sima_qian_git_run_failed} = error} =
             Git.clone(remote, Path.join(dir, "x"))

    assert error.details[:output] =~ "fatal:"
    refute inspect(error) =~ @token
  end

  test "the token reaches git through a private file and never its arguments", %{remote: remote} do
    seen =
      Git.credentialed(remote, fn url, config ->
        file =
          config |> List.last() |> String.replace_prefix("credential.helper=store --file=", "")

        %{
          url: url,
          config: config,
          stored: File.read!(file),
          mode: File.stat!(file).mode &&& 0o777,
          file: file
        }
      end)

    assert seen.url == "https://github.com/example/private.git"
    refute Enum.any?([seen.url | seen.config], &(&1 =~ @token))
    assert seen.config |> Enum.take(2) == ["-c", "credential.helper="]
    # scheme, userinfo and host only: a stored path would never match.
    assert seen.stored == "https://x-access-token:#{@token}@github.com\n"
    assert seen.mode == 0o600
    refute File.exists?(seen.file)
  end

  test "a remote with no userinfo passes through untouched", %{dir: dir} do
    assert Git.credentialed(dir, fn url, config -> {url, config} end) == {dir, []}
  end
end
