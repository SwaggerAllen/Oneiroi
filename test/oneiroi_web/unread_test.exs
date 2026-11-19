defmodule OneiroiWeb.UnreadTest do
  @moduledoc """
  The witness's unread by workspace (gaia#58, seshat#96; the witness,
  2026-11-19: an unread count next to every workspace). A first look
  starts from now; her chat counts what she said after the mark; the
  house counts others' posts after each thread's mark.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    witness = Actor.new(:witness, account.id)

    {:ok, _} =
      Seshat.household_propose_contract(witness, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    resident = Fixtures.resident!(account)
    Fixtures.agreed!(resident.id, account.id)
    :ok = Gaia.store_key(account.id, "sk-or-test", witness)
    on_exit(fn -> File.rm_rf!(SimaQian.Household.dir(account.id)) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, account: account, witness: witness, resident: resident}
  end

  test "her chat: what she says after the witness's mark counts, and a later mark clears it",
       ctx do
    by = fn body -> Enum.find(body["residents"], &(&1["id"] == ctx.resident.id))["count"] end
    earlier = Clock.now() |> DateTime.add(-60) |> DateTime.to_iso8601()

    assert ctx.conn
           |> put("/v1/unread", %{subject: ctx.resident.id, at: earlier})
           |> response(204)

    assert by.(ctx.conn |> get("/v1/unread") |> json_response(200)) == 0

    {:ok, key} = Kumbukumbu.main_session(ctx.resident.id, ctx.account.id, ctx.witness)
    Model.reply("Good morning.", for: ctx.resident.id)
    on_exit(fn -> Model.clear(for: ctx.resident.id) end)
    {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, key, "hello", ctx.witness)

    assert by.(ctx.conn |> get("/v1/unread") |> json_response(200)) == 1

    at = Clock.now() |> DateTime.add(1) |> DateTime.to_iso8601()
    assert ctx.conn |> put("/v1/unread", %{subject: ctx.resident.id, at: at}) |> response(204)
    assert by.(ctx.conn |> get("/v1/unread") |> json_response(200)) == 0
  end

  test "the house: another member's post counts by thread until that thread is marked", ctx do
    assert %{"house" => %{"count" => 0}} = ctx.conn |> get("/v1/unread") |> json_response(200)

    Clock.Fake.advance(1)
    resident = Actor.new(:resident, ctx.resident.id)

    {:ok, %{path: thread}} =
      Seshat.household_post(resident, %{"title" => "Herons", "content" => "At the weir."})

    assert %{
             "house" => %{
               "count" => 1,
               "threads" => %{^thread => 1},
               "seen" => %{^thread => mark}
             }
           } =
             ctx.conn |> get("/v1/unread") |> json_response(200)

    # Where it was read up to (seshat#97): the first look's baseline,
    # before the post, so the thread opens at the post.
    {:ok, mark, _} = DateTime.from_iso8601(mark)
    assert DateTime.compare(mark, Clock.now()) == :lt

    # His own post never counts.
    {:ok, _} = Seshat.household_post(ctx.witness, %{"title" => "Mine", "content" => "Mine."})
    assert %{"house" => %{"count" => 1}} = ctx.conn |> get("/v1/unread") |> json_response(200)

    # The shelf, last updated first (the witness, 2026-11-19): his newer
    # thread leads until a reply brings the older one up.
    order = fn ->
      {:ok, shelf} = Seshat.household_shelf(ctx.witness, 0)
      Enum.map(shelf.threads, & &1.title)
    end

    assert order.() == ["Mine", "Herons"]
    Clock.Fake.advance(1)
    {:ok, _} = Seshat.household_reply(ctx.witness, thread, %{"content" => "Saw one too."})
    assert order.() == ["Herons", "Mine"]

    at = Clock.now() |> DateTime.add(1) |> DateTime.to_iso8601()

    assert ctx.conn
           |> put("/v1/unread", %{subject: "house", thread: thread, at: at})
           |> response(204)

    assert %{"house" => %{"count" => 0}} = ctx.conn |> get("/v1/unread") |> json_response(200)

    assert ctx.conn |> put("/v1/unread", %{subject: "someone else", at: at}) |> json_response(422)
  end
end
