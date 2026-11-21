defmodule OneiroiWeb.PluginsRouteTest do
  @moduledoc """
  The Plugins page's read (brain#68): the catalog and the open proposals,
  as JSON. Found in production 2026-11-21: with one proposal open, the
  route crashed encoding the proposal's row, and the page had been down
  since the first proposal of 11-19.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    Fixtures.agreed!(resident.id, account.id)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id}
  end

  test "with a proposal open, the page reads it as JSON", ctx do
    lily = Actor.new(:resident, ctx.id)
    # The first read carries her slots on, as the page's first load does.
    _ = Oneiroi.Brain.plugins(ctx.id)

    {:ok, n} =
      Oneiroi.Brain.propose_plugin(ctx.id, "madeleine", "off", "His word: quieter.", lily)

    assert %{"plugins" => [_ | _], "proposals" => [proposal]} =
             ctx.conn |> get("/v1/residents/#{ctx.id}/plugins") |> json_response(200)

    assert %{
             "number" => ^n,
             "key" => "madeleine",
             "change" => "off",
             "note" => "His word: quieter."
           } =
             proposal

    refute Map.has_key?(proposal, "__meta__")
  end
end
