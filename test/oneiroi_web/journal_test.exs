defmodule OneiroiWeb.JournalTest do
  @moduledoc "The journal over HTTP: days, one day, an entry, a todo done."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:steward, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id}
  end

  test "the journal's routes", %{conn: conn, id: id} do
    base = "/v1/residents/#{id}/journal"
    assert [] = conn |> get(base) |> json_response(200)
    assert conn |> get("#{base}/2026-10-26") |> json_response(404)

    assert %{"day" => "2026-10-26", "number" => 1, "kind" => "plan"} =
             conn
             |> post("#{base}/2026-10-26/entries", %{kind: "plan", text: "Bake."})
             |> json_response(200)

    assert %{"number" => 2} =
             conn
             |> post("#{base}/2026-10-26/entries", %{kind: "todo", text: "Flour"})
             |> json_response(200)

    assert conn
           |> post("#{base}/2026-10-26/entries", %{kind: "poem", text: "x"})
           |> json_response(422)

    assert conn |> post("#{base}/2026-10-26/entries/2/done") |> response(204)
    assert conn |> post("#{base}/2026-10-26/entries/9/done") |> json_response(404)

    assert %{
             "entries" => [
               %{"number" => 1, "by" => "steward"},
               %{"number" => 2, "done_at" => done}
             ],
             "delta" => %{"plan" => 1, "done" => 1, "unwrapped" => true}
           } =
             conn |> get("#{base}/2026-10-26") |> json_response(200)

    assert is_binary(done)

    assert [%{"day" => "2026-10-26", "delta" => %{"todo" => 1}}] =
             conn |> get(base) |> json_response(200)
  end
end
