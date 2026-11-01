defmodule OneiroiWeb.ResidentBackupTest do
  @moduledoc "The resident's response says where its records are pushed and when the last push landed, and never the token."
  use OneiroiWeb.ConnCase, async: false

  # 2026-11-01: the witness set Lily's backup remote, read the resident
  # back, saw only the import's source, and took the call for a failure.
  # The remote was set; the response did not say so.

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Git

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    bare =
      Path.join(System.tmp_dir!(), "oneiroi-web-remote-#{System.unique_integer([:positive])}")

    :ok = Git.init_bare(bare)

    on_exit(fn ->
      File.rm_rf!(bare)
      File.rm_rf!(Backup.dir(resident.id))
    end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, account: account, resident: resident, bare: bare}
  end

  test "the remote and the last backup, with its time and commit", ctx do
    path = "/v1/residents/#{ctx.resident.id}"

    assert %{"remote" => nil, "last_backup" => %{"at" => nil, "commit" => nil}} =
             ctx.conn |> get(path) |> json_response(200)

    ctx.conn
    |> put(path <> "/remote", %{url: ctx.bare, token: "github_pat_TESTONLY"})
    |> response(204)

    Clock.Fake.advance(120)
    actor = Oneiroi.Actor.new(:witness, ctx.account.id)
    assert {:ok, %{commits: commits}} = Oneiroi.SimaQian.backup(ctx.resident.id, actor)
    {_class, sha} = List.last(commits)

    body = ctx.conn |> get(path) |> response(200)
    refute body =~ "github_pat_TESTONLY"

    assert %{"remote" => remote, "last_backup" => %{"at" => at, "commit" => ^sha}} =
             Jason.decode!(body)

    assert remote == ctx.bare
    assert {:ok, at, 0} = DateTime.from_iso8601(at)
    assert DateTime.compare(at, Clock.now()) != :gt
  end
end
