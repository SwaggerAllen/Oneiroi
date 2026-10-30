defmodule OneiroiWeb.WashTest do
  @moduledoc "The wash pass over HTTP: the witness runs it and reads its runs and flags; another account sees nothing."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    other = Fixtures.account!()
    witness = Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", witness)

    :ok =
      AgathosDaimon.write_file(
        resident.id,
        "SOUL.md",
        "# Soul\n\nI will have moved by spring.",
        %{},
        witness
      )

    Model.clear()

    Model.script(fn _request -> {:ok, "FLAG [2] | expired | spring has passed\nSUMMARY: one"} end,
      for: resident.id
    )

    on_exit(fn -> Model.clear(for: resident.id) end)
    {:ok, conn: login(account), other_conn: login(other), id: resident.id}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  test "the wash's routes", %{conn: conn, other_conn: other_conn, id: id} do
    assert %{"ref" => ref} =
             conn |> post("/v1/residents/#{id}/wash/run", %{}) |> json_response(201)

    assert %{
             "runs" => [%{"ref" => ^ref, "outcome" => "ok", "entries" => 2, "flagged" => 1}],
             "open" => [
               %{
                 "kind" => "expired",
                 "file" => "SOUL.md",
                 "entry" => "[soul/1] I will have moved by spring.",
                 "decision" => nil
               }
             ],
             "decided" => []
           } = conn |> get("/v1/residents/#{id}/wash") |> json_response(200)

    assert other_conn |> get("/v1/residents/#{id}/wash") |> json_response(404)
  end
end
