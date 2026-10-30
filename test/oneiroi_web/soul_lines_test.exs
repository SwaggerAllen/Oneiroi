defmodule OneiroiWeb.SoulLinesTest do
  @moduledoc "The soul's lines over HTTP: the witness reads them in order with their numbers; another account sees nothing."
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
    witness = Actor.new(:witness, account.id)

    :ok =
      AgathosDaimon.write_file(
        resident.id,
        "SOUL.md",
        "# Soul\n\nCurious.\n\nSlow to anger.",
        %{},
        witness
      )

    :ok =
      AgathosDaimon.write_file(
        resident.id,
        "SOUL.md",
        "# Soul\n\n[soul/2] Slow to anger.\n\n[soul/1] Curious, still.",
        %{cites: [3]},
        witness
      )

    {:ok, conn: login(account), other_conn: login(other), id: resident.id}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "the lines' route", %{conn: conn, other_conn: other_conn, id: id} do
    assert [
             %{
               "number" => 2,
               "text" => "Slow to anger.",
               "position" => 1,
               "cites" => [],
               "version" => 1
             },
             %{
               "number" => 1,
               "text" => "Curious, still.",
               "position" => 2,
               "cites" => [3],
               "version" => 2
             }
           ] = conn |> get("/v1/residents/#{id}/soul-lines") |> json_response(200)

    assert %{"content" => "# Soul\n\n[soul/2] Slow to anger.\n\n[soul/1] Curious, still."} =
             conn |> get("/v1/residents/#{id}/files/SOUL.md") |> json_response(200)

    assert other_conn |> get("/v1/residents/#{id}/soul-lines") |> json_response(404)
  end
end
