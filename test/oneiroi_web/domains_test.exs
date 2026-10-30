defmodule OneiroiWeb.DomainsTest do
  @moduledoc "A session's room over HTTP (spec §6.3, P23): opened with a domain, listed with it, refused when it is not a slug."
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

  test "a domain on the session", %{conn: conn, id: id} do
    assert %{"key" => key} =
             conn
             |> post("/v1/residents/#{id}/sessions", %{kind: "free_time", domain: "business"})
             |> json_response(201)

    assert %{"error" => %{"kind" => "kumbukumbu_domain_invalid"}} =
             conn
             |> post("/v1/residents/#{id}/sessions", %{kind: "free_time", domain: "Business!"})
             |> json_response(422)

    sessions = conn |> get("/v1/residents/#{id}/sessions") |> json_response(200)
    assert %{"domain" => "business"} = Enum.find(sessions, &(&1["key"] == key))
  end
end
