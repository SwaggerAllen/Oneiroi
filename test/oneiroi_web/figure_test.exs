defmodule OneiroiWeb.FigureTest do
  @moduledoc "Figures, the steward's audits and the light over HTTP."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id}
  end

  test "figures, checks and the light", %{conn: conn, id: id} do
    assert conn
           |> post("/v1/residents/#{id}/figures", %{key: "tea", label: "Cups of tea"})
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/figures", %{key: "Bad Key", label: "x"})
           |> json_response(422)

    assert conn
           |> post("/v1/residents/#{id}/figures/tea/increment", %{by: 2, note: "two"})
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/figures/coffee/increment", %{note: "x"})
           |> json_response(404)

    assert [%{"key" => "tea", "kind" => "counter", "value" => 2}] =
             conn |> get("/v1/residents/#{id}/figures") |> json_response(200)

    assert %{
             "value" => 2,
             "recent" => [%{"by" => 2, "note" => "two", "actor" => %{"kind" => "steward"}}]
           } = conn |> get("/v1/residents/#{id}/figures/tea") |> json_response(200)

    assert conn |> get("/v1/residents/#{id}/figures/nope") |> json_response(404)

    assert conn
           |> post("/v1/residents/#{id}/checks", %{
             key: "tea-enough",
             label: "Enough tea",
             figure: "tea",
             op: ">=",
             value: 3,
             tone: "fail"
           })
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/checks", %{
             key: "bad",
             label: "x",
             figure: "tea",
             op: "!",
             value: 3
           })
           |> json_response(422)

    assert %{
             "state" => "fail",
             "findings" => [%{"key" => "tea-enough", "tone" => "fail", "value" => 2}]
           } =
             conn |> post("/v1/residents/#{id}/checks/run", %{}) |> json_response(200)

    assert %{"state" => "fail"} = conn |> get("/v1/residents/#{id}/light") |> json_response(200)
    checks = conn |> get("/v1/residents/#{id}/checks") |> json_response(200)
    assert Enum.count(checks, & &1["builtin"]) == 5
    assert %{"last" => %{"tone" => "fail"}} = Enum.find(checks, &(&1["key"] == "tea-enough"))

    assert conn |> delete("/v1/residents/#{id}/checks/tea-enough") |> response(204)
    assert conn |> delete("/v1/residents/#{id}/checks/tea-enough") |> json_response(404)
    assert conn |> delete("/v1/residents/#{id}/figures/tea") |> response(204)
    assert [] = conn |> get("/v1/residents/#{id}/figures") |> json_response(200)
  end
end
