defmodule OneiroiWeb.HouseRoutesTest do
  @moduledoc "The witness's reads of the house: the letters between conversations (kumbukumbu #44) and how retrieval has been used (kumbukumbu #43), the same numbers and words the resident reads; another account reads neither."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:witness, account.id)
    lily = Oneiroi.Actor.new(:resident, resident.id)
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, actor)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, id: resident.id, key: key, lily: lily}
  end

  test "the letters and the retrieval counts read as the resident's witness, and not by a stranger",
       ctx do
    {:ok, _} =
      Kumbukumbu.send_letter(ctx.id, ctx.key, %{to: "house", text: "The log is open."}, ctx.lily)

    :ok =
      Kumbukumbu.record_retrieval(
        ctx.id,
        ctx.key,
        "t1",
        [%{target: "bookmark/1", stage: "used", via: "bookmark_open"}],
        ctx.lily
      )

    assert [
             %{
               "number" => 1,
               "from" => "Oneiroi chat",
               "to" => "house",
               "text" => "The log is open.",
               "read_by" => []
             }
           ] =
             ctx.conn |> get("/v1/residents/#{ctx.id}/letters") |> json_response(200)

    assert [%{"target" => "bookmark/1", "used" => 1, "returned" => 0, "considered" => 0}] =
             ctx.conn |> get("/v1/residents/#{ctx.id}/retrieval") |> json_response(200)

    stranger = Fixtures.account!()

    other =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: stranger.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    assert other |> get("/v1/residents/#{ctx.id}/letters") |> json_response(404)
    assert other |> get("/v1/residents/#{ctx.id}/retrieval") |> json_response(404)

    assert other
           |> post("/v1/residents/#{ctx.id}/letters", %{to: "house", text: "x"})
           |> json_response(404)
  end

  # The witness writes letters too: a brief to Free time is the queue's
  # front door from the client; a name nobody answers to is refused.
  test "the witness writes a house letter to a name the house answers to, and reads the names",
       ctx do
    names = ctx.conn |> get("/v1/residents/#{ctx.id}/letters/addresses") |> json_response(200)
    assert ["house", "Free time", "Oneiroi chat" | _] = names

    assert %{"number" => 1} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/letters", %{
               to: "Free time",
               text: "Read the scrape pass."
             })
             |> json_response(201)

    assert [%{"from" => "witness", "to" => "Free time"}] =
             ctx.conn |> get("/v1/residents/#{ctx.id}/letters") |> json_response(200)

    assert %{"error" => %{"kind" => "kumbukumbu_letter_unaddressed"}} =
             ctx.conn
             |> post("/v1/residents/#{ctx.id}/letters", %{to: "nobody", text: "x"})
             |> json_response(422)
  end
end
