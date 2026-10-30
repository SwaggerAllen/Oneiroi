defmodule OneiroiWeb.ReportTest do
  @moduledoc "Reports over HTTP: filed by the witness, investigated and resolved by an investigator from its own session, read by both."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    investigator = Fixtures.account!("investigator@example.org")
    {:ok, conn: login(account), investigator_conn: login(investigator), id: resident.id}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "the reports' routes", %{conn: conn, investigator_conn: inv, id: id} do
    base = "/v1/residents/#{id}/reports"
    assert %{"number" => 1} = conn |> post(base, %{text: "She ignores me."}) |> json_response(200)
    assert conn |> post(base, %{text: " "}) |> json_response(422)
    assert inv |> post(base, %{text: "not mine to file"}) |> json_response(403)

    assert conn |> post("#{base}/1/steps", %{reason: "x"}) |> json_response(403)
    assert inv |> post("#{base}/1/steps", %{reason: "read the week"}) |> response(204)
    assert inv |> post("#{base}/9/steps", %{reason: "x"}) |> json_response(404)

    assert %{"outcome" => "strike", "strike" => %{"number" => 1, "consequence" => "fine"}} =
             inv
             |> post("#{base}/1/resolve", %{outcome: "strike", note: "a first"})
             |> json_response(200)

    assert %{
             "reports" => [
               %{
                 "number" => 1,
                 "state" => "resolved",
                 "steps" => [%{"reason" => "read the week"}]
               }
             ],
             "strikes" => [%{"number" => 1}]
           } =
             conn |> get(base) |> json_response(200)

    assert %{"reports" => [_]} = inv |> get(base) |> json_response(200)
  end
end
