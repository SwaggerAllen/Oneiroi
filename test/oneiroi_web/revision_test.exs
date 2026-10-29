defmodule OneiroiWeb.RevisionTest do
  @moduledoc "Revisions over HTTP: a steward's fact applies, its stance is proposed, and the list shows both."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:steward, account.id)
    brain = Oneiroi.Actor.new(:resident, resident.id)
    {:ok, key} = Oneiroi.Kumbukumbu.main_session(resident.id, account.id, actor)

    {:ok, n} =
      Oneiroi.Kumbukumbu.add_bookmark(
        resident.id,
        %{
          session_key: key,
          anchor_ref: "t1",
          line: "a line",
          summary: "s",
          turns_back: 1,
          anchor_at: Clock.now()
        },
        brain
      )

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, bookmark: n}
  end

  test "the revisions' routes", %{conn: conn, id: id, bookmark: n} do
    base = "/v1/residents/#{id}/revisions"
    assert [] = conn |> get(base) |> json_response(200)

    assert %{"number" => 1, "state" => "applied"} =
             conn
             |> post(base, %{
               target_kind: "bookmark",
               target_id: n,
               kind: "fact",
               text: "x",
               note: "why"
             })
             |> json_response(200)

    assert %{"number" => 2, "state" => "proposed"} =
             conn
             |> post(base, %{
               target_kind: "bookmark",
               target_id: n,
               kind: "stance",
               text: "y",
               note: "why"
             })
             |> json_response(200)

    assert conn
           |> post(base, %{
             target_kind: "bookmark",
             target_id: n,
             kind: "mood",
             text: "y",
             note: "why"
           })
           |> json_response(422)

    assert [
             %{"number" => 2, "state" => "proposed", "by" => %{"kind" => "steward"}},
             %{"number" => 1, "kind" => "fact", "note" => "why"}
           ] =
             conn |> get(base) |> json_response(200)
  end
end
