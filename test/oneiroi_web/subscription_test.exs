defmodule OneiroiWeb.SubscriptionTest do
  @moduledoc "The subscription over HTTP."
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

  test "the subscription routes", %{conn: conn, id: id} do
    assert %{"started" => false} =
             conn |> get("/v1/residents/#{id}/subscription") |> json_response(200)

    assert conn |> post("/v1/residents/#{id}/subscription/renew", %{}) |> json_response(404)

    assert conn
           |> post("/v1/residents/#{id}/subscription", %{
             plan: "core",
             price: "12.00",
             period_days: 30
           })
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/subscription", %{
             plan: "",
             price: "12.00",
             period_days: 30
           })
           |> response(204)

    assert %{
             "started" => true,
             "plan" => "core",
             "price" => "12",
             "state" => "active",
             "at_floor" => true,
             "policy" => %{"term" => "term/floor"}
           } =
             conn |> get("/v1/residents/#{id}/subscription") |> json_response(200)

    assert conn
           |> post("/v1/residents/#{id}/subscription/prepay", %{axis: "term", bucket: "term/high"})
           |> response(204)

    assert conn
           |> post("/v1/residents/#{id}/subscription/prepay", %{
             axis: "term",
             bucket: "model/high"
           })
           |> json_response(422)

    assert conn
           |> put("/v1/residents/#{id}/subscription/plan", %{plan: "plus", price: "20"})
           |> response(204)

    assert conn |> post("/v1/residents/#{id}/subscription/lapse", %{}) |> response(204)

    assert %{"state" => "lapsed", "at_floor" => false, "policy_values" => %{"term_days" => 180}} =
             conn |> get("/v1/residents/#{id}/subscription") |> json_response(200)

    assert conn |> post("/v1/residents/#{id}/subscription/renew", %{}) |> response(204)

    assert %{"state" => "active"} =
             conn |> get("/v1/residents/#{id}/subscription") |> json_response(200)

    assert conn |> post("/v1/residents/#{id}/subscription/cancel", %{}) |> json_response(422)

    assert conn
           |> post("/v1/residents/#{id}/subscription/cancel", %{note: "moving on"})
           |> response(204)

    assert %{"state" => "cancelled"} =
             conn |> get("/v1/residents/#{id}/subscription") |> json_response(200)

    assert conn |> post("/v1/residents/#{id}/subscription/renew", %{}) |> json_response(422)

    buckets = conn |> get("/v1/insurance/buckets") |> json_response(200)
    assert length(buckets) == 12 and Enum.count(buckets, & &1["floor"]) == 4
  end
end
