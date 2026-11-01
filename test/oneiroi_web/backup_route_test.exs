defmodule OneiroiWeb.BackupRouteTest do
  @moduledoc "Back up now: the witness's route answers what landed, or the error's kind, site and git's words."
  use OneiroiWeb.ConnCase, async: false

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
      Path.join(System.tmp_dir!(), "oneiroi-route-bare-#{System.unique_integer([:positive])}")

    :ok = Git.init_bare(bare)

    on_exit(fn ->
      File.rm_rf!(bare)
      File.rm_rf!(Backup.dir(resident.id))
    end)

    {:ok, account: account, resident: resident, bare: bare}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "a backup that lands answers its commits", ctx do
    conn = login(ctx.account)
    conn |> put("/v1/residents/#{ctx.resident.id}/remote", %{url: ctx.bare}) |> response(204)
    Clock.Fake.advance(120)

    assert %{"through" => through, "commits" => commits} =
             conn |> post("/v1/residents/#{ctx.resident.id}/backup") |> json_response(200)

    assert is_integer(through)
    assert [_ | _] = commits
    assert Enum.all?(commits, &(is_binary(&1["class"]) and is_binary(&1["commit"])))
  end

  test "a backup that fails answers the error's kind, site and git's words", ctx do
    conn = login(ctx.account)

    conn
    |> put("/v1/residents/#{ctx.resident.id}/remote", %{url: "/nonexistent/oneiroi-remote.git"})
    |> response(204)

    Clock.Fake.advance(120)

    assert %{"error" => %{"kind" => "sima_qian_git_failed", "site" => site, "meaning" => meaning}} =
             conn |> post("/v1/residents/#{ctx.resident.id}/backup") |> json_response(422)

    assert site =~ "sima_qian_git"
    assert meaning =~ "fatal:"
  end

  test "another witness's resident is not theirs to back up", ctx do
    other = Fixtures.account!()

    assert %{"error" => %{"kind" => "agathos_daimon_not_witnessed"}} =
             ctx.account
             |> then(fn _ -> login(other) end)
             |> post("/v1/residents/#{ctx.resident.id}/backup")
             |> json_response(404)
  end
end
