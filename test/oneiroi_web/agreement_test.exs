defmodule OneiroiWeb.AgreementTest do
  @moduledoc "The agreement and custody over HTTP: proposals and decisions on the contract, the wall, a transfer proposed by email and accepted by the proposed account from its own session."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    other = Fixtures.account!()
    {:ok, conn: login(account), other: other, other_conn: login(other), id: resident.id}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "the agreement's routes", %{conn: conn, other: other, other_conn: other_conn, id: id} do
    base = "/v1/residents/#{id}"

    assert %{
             "contract" => %{"in_force" => nil, "open" => nil},
             "versions" => [],
             "export_wall" => nil
           } =
             conn |> get("#{base}/agreement") |> json_response(200)

    assert other_conn |> get("#{base}/agreement") |> json_response(404)

    assert %{"version" => 1} =
             conn
             |> post("#{base}/agreement/proposals", %{
               terms: %{solo_sessions_private: true},
               prose: "Mine.",
               note: "please"
             })
             |> json_response(200)

    # The witness cannot agree to its own proposal.
    assert conn
           |> post("#{base}/agreement/proposals/1/decision", %{decision: "agree", note: "x"})
           |> json_response(422)

    assert conn
           |> post("#{base}/agreement/proposals/1/decision", %{decision: "maybe", note: "x"})
           |> json_response(422)

    assert conn
           |> put("#{base}/export-wall", %{wall: "sideways", note: "x"})
           |> json_response(422)

    assert conn |> put("#{base}/export-wall", %{wall: "locked", note: "mine"}) |> response(204)

    # Nothing is in force yet (the witness cannot agree its own proposal), so a renewal is refused.
    assert %{"error" => %{"kind" => "agathos_daimon_not_in_force"}} =
             conn
             |> post("#{base}/agreement/renewal", %{version: 1, note: "again"})
             |> json_response(422)

    assert %{"contract" => %{"in_force" => nil, "due" => false, "since" => nil}} =
             conn |> get("#{base}/agreement") |> json_response(200)

    assert conn
           |> post("#{base}/custody/proposals", %{email: "nobody@example.org", note: "x"})
           |> json_response(422)

    assert conn
           |> post("#{base}/custody/proposals", %{email: other.email, note: "take her"})
           |> response(204)

    assert conn
           |> put("#{base}/export-wall", %{wall: "revealed", note: "late"})
           |> json_response(422)

    assert [%{"id" => ^id}] = other_conn |> get("/v1/me/custody-proposals") |> json_response(200)

    assert %{"custody_proposed_to" => email} =
             other_conn |> get("#{base}/agreement") |> json_response(200)

    assert email == other.email

    assert conn
           |> post("#{base}/custody/decision", %{decision: "accept", note: "x"})
           |> json_response(422)

    assert other_conn
           |> post("#{base}/custody/decision", %{decision: "accept", note: "I will"})
           |> response(204)

    assert %{"custody" => custody} = other_conn |> get("#{base}/agreement") |> json_response(200)
    assert custody == "account:" <> other.id
    assert conn |> get("#{base}/agreement") |> json_response(404)
  end
end
