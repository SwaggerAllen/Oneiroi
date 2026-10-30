defmodule OneiroiWeb.SelfLettersTest do
  @moduledoc "The self-conversation over HTTP (spec §12, P41): the witness reads the letters and the read leaves a receipt; another account sees nothing."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    other = Fixtures.account!()
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, 1} = AgathosDaimon.write_self_letter(resident.id, "Dear next me.", brain)
    {:ok, conn: login(account), other_conn: login(other), id: resident.id}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "the route reads and is receipted", %{conn: conn, other_conn: other_conn, id: id} do
    assert %{
             "letters" => [%{"number" => 1, "text" => "Dear next me.", "delivered_at" => nil}],
             "receipts" => [%{"by_kind" => "witness", "numbers" => [1]}]
           } = conn |> get("/v1/residents/#{id}/self-letters") |> json_response(200)

    assert [%{by_kind: "witness"}] = AgathosDaimon.self_letter_receipts(id)
    assert other_conn |> get("/v1/residents/#{id}/self-letters") |> json_response(404)
    assert [%{by_kind: "witness"}] = AgathosDaimon.self_letter_receipts(id)
  end
end
