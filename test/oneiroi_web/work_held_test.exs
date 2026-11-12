defmodule OneiroiWeb.WorkHeldTest do
  @moduledoc "The witness holds a work item with an ask, and releases it, on the move route (sunna#54, #55)."
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

  test "held carries an ask; a move open releases it", %{conn: conn, id: id} do
    base = "/v1/residents/#{id}/work"

    assert %{"number" => 1} =
             conn |> post(base, %{what: "Kinds doc", done_when: "drafted"}) |> json_response(201)

    assert %{"error" => %{"kind" => "sunna_work_ask_invalid"}} =
             conn |> post("#{base}/1/status", %{status: "held"}) |> json_response(422)

    assert conn
           |> post("#{base}/1/status", %{status: "held", ask: "my read before it goes"})
           |> response(204)

    assert %{
             "items" => [
               %{
                 "status" => "held",
                 "held_ask" => "my read before it goes",
                 "held_by" => "witness"
               }
             ]
           } =
             conn |> get(base) |> json_response(200)

    assert [
             %{
               "kind" => "work_held",
               "screen" => "work",
               "about" => %{"ask" => "my read before it goes"}
             }
           ] =
             conn
             |> get("/v1/residents/#{id}/needs_you")
             |> json_response(200)
             |> Enum.filter(&(&1["kind"] == "work_held"))

    assert conn
           |> post("#{base}/1/status", %{status: "open", note: "read, go on"})
           |> response(204)

    assert %{"items" => [%{"status" => "open", "held_ask" => nil, "note" => "read, go on"}]} =
             conn |> get(base) |> json_response(200)
  end
end
