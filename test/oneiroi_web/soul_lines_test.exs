defmodule OneiroiWeb.SoulLinesTest do
  @moduledoc "The soul's lines over HTTP: the witness reads them in order with their numbers; another account sees nothing."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

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

    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, witness)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        resident.id,
        key,
        "t1",
        at,
        [%{role: :assistant, content: "Slowly.", sent_at: at, actor: brain}],
        brain
      )

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        resident.id,
        %{
          session_key: key,
          anchor_ref: "t1",
          anchor_at: at,
          line: "slowly",
          summary: "s",
          turns_back: 1
        },
        brain
      )

    {:ok, conn: login(account), other_conn: login(other), id: resident.id, bookmark: n}
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

  test "a pin as evidence of a line: the pin carries the line, the line counts the citation", %{
    conn: conn,
    id: id,
    bookmark: n
  } do
    assert conn
           |> post("/v1/residents/#{id}/bookmarks/#{n}/pin", %{evidences: 9})
           |> json_response(422)

    assert conn
           |> post("/v1/residents/#{id}/bookmarks/#{n}/pin", %{evidences: 2})
           |> response(204)

    assert %{"bookmark" => %{"pin_evidences" => 2, "tags" => ["soul/2"]}} =
             conn |> get("/v1/residents/#{id}/bookmarks/#{n}") |> json_response(200)

    assert [%{"number" => 2, "citations" => 1, "days" => 1}, %{"number" => 1, "citations" => 0}] =
             conn |> get("/v1/residents/#{id}/soul-lines") |> json_response(200)
  end
end
