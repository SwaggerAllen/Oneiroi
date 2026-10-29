defmodule OneiroiWeb.HonchoTest do
  @moduledoc "The bridge and the memory audit over HTTP."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Actor.new(:steward, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, account: account, actor: actor}
  end

  test "the bridge and the audits", %{conn: conn, id: id, account: account, actor: actor} do
    assert %{"provisioned" => false} =
             conn |> get("/v1/residents/#{id}/honcho") |> json_response(200)

    assert conn |> post("/v1/residents/#{id}/honcho/card-audit", %{}) |> json_response(404)

    :ok = Proteus.provision(id, actor)

    assert %{"provisioned" => true, "workspace" => ^id, "card" => %{"source" => "provision"}} =
             conn |> get("/v1/residents/#{id}/honcho") |> json_response(200)

    assert %{"moved" => false} =
             conn |> post("/v1/residents/#{id}/honcho/card-audit", %{}) |> json_response(200)

    Honcho.put_conclusions(id, "resident-" <> id, "steward-" <> account.id, [
      %{id: "c1", content: "Allergic to cats."}
    ])

    Model.reply("FLAG [1] | one remark\nSUMMARY: thin", for: id)

    assert %{"ref" => _} =
             conn |> post("/v1/residents/#{id}/audits/run", %{}) |> json_response(201)

    assert %{"runs" => [%{"flagged" => 1}], "open" => [%{"ref" => ref}]} =
             conn |> get("/v1/residents/#{id}/audits") |> json_response(200)

    assert conn
           |> post("/v1/residents/#{id}/audits/flags/#{ref}", %{decision: "approve"})
           |> json_response(422)

    assert conn
           |> post("/v1/residents/#{id}/audits/flags/#{ref}", %{decision: "approve", note: "true"})
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/audits/flags/#{ref}", %{decision: "delete", note: "x"})
           |> json_response(422)

    assert conn
           |> post("/v1/residents/#{id}/audits/flags/nope", %{decision: "delete", note: "x"})
           |> json_response(404)

    assert %{"open" => [], "decided" => [%{"decision" => "approved"}]} =
             conn |> get("/v1/residents/#{id}/audits") |> json_response(200)
  end
end
