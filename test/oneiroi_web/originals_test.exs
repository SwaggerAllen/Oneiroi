defmodule OneiroiWeb.OriginalsTest do
  @moduledoc "The originals import over HTTP (sima-qian #40): the witness's route, and the source's token in no response and no log line."
  use OneiroiWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian

  @identity ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]
  @token "github_pat_ORIGINALS_TESTONLY_7f3a"

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    actor = Oneiroi.Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    resident = Fixtures.resident!(account)
    {:ok, dir} = SimaQian.repository_dir(resident.id)

    work = Path.join(System.tmp_dir!(), "oneiroi-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(work, "memory"))
    File.write!(Path.join(work, "memory/2026-01-01.md"), "# Day one\n")
    git!(work, ["init", "-q", "-b", "main"])
    git!(work, ["add", "-A"])
    git!(work, ["commit", "-q", "-m", "the fork"])
    commit = git!(work, ["rev-parse", "HEAD"])

    on_exit(fn ->
      File.rm_rf!(work)
      File.rm_rf!(dir)
    end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, resident: resident, source: "file://" <> work, commit: commit}
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", @identity ++ args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  test "the witness imports at a commit with a token; the token is in no response and no log line",
       ctx do
    path = "/v1/residents/#{ctx.resident.id}/originals"
    body = %{source: ctx.source, commit: ctx.commit, token: @token}

    {conn, log} = with_log(fn -> post(ctx.conn, path, body) end)

    assert %{
             "written" => ["memory/2026-01-01.md"],
             "adopted" => ["memory/2026-01-01.md"],
             "commit" => commit,
             "source" => source
           } = json_response(conn, 200)

    assert commit == ctx.commit and source == ctx.source
    refute conn.resp_body =~ @token
    refute log =~ @token

    # A commit the source does not have: git's words come back, the token does not.
    missing = %{body | commit: String.duplicate("e", 40)}
    {conn, log} = with_log(fn -> post(ctx.conn, path, missing) end)
    assert %{"error" => _} = json_response(conn, 422)
    refute conn.resp_body =~ @token
    refute log =~ @token
  end

  test "a resident this account does not witness is not found", ctx do
    other = Fixtures.resident!(Fixtures.account!())

    conn =
      post(ctx.conn, "/v1/residents/#{other.id}/originals", %{
        source: ctx.source,
        commit: ctx.commit
      })

    assert json_response(conn, 404)
    {:ok, other_dir} = SimaQian.repository_dir(other.id)
    on_exit(fn -> File.rm_rf!(other_dir) end)
    refute File.exists?(Path.join(other_dir, "memory"))
  end
end
