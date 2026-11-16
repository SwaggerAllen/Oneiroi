defmodule OneiroiWeb.PresenceRoutesTest do
  @moduledoc """
  xenia#20 over HTTP: the witness turns presence on, fetches and masks the
  follow list and decides what was staged; the reader sees what is due in
  /waiting by number alone, reads it from its route with the origin each
  goes from, and says it went; a brain token reaches none of it.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Xenia
  alias Oneiroi.Xenia.Substack.Fake

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    on_exit(&Fake.clear/0)
    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:witness, account.id)
    {:ok, reader} = AgathosDaimon.register_adapter(resident.id, "scrape", "reader", actor)
    {:ok, brain} = AgathosDaimon.register_adapter(resident.id, "claude-code", "brain", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     reader: reader,
     brain: brain,
     her: Oneiroi.Actor.new(:resident, resident.id, "fake/model"),
     witness: login(account)}
  end

  defp login(account) do
    build_conn()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
    |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
    |> recycle()
    |> put_req_header("origin", OneiroiWeb.Endpoint.url())
  end

  defp bearer(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  test "the witness's switch, list, mask and review; the reader's due list and receipt", ctx do
    id = ctx.id

    Fake.put_profile(42, [
      %{
        key: "seven",
        name: "Seven",
        host: "https://seven.substack.com",
        publication_id: 1,
        author_id: 7
      }
    ])

    Fake.put_items("seven", [
      %{
        key: "p-11",
        kind: "post",
        account: "seven",
        title: "The Garden",
        url: "https://seven.substack.com/p/the-garden",
        at: DateTime.add(Clock.now(), -3600),
        likes: 4,
        comments: 1,
        restacks: 0,
        excerpt: "On tending."
      }
    ])

    assert ctx.witness
           |> put("/v1/residents/#{id}/presence", %{enabled: true, handle: "allenstrut"})
           |> response(204)

    assert %{"accounts" => 1} =
             ctx.witness |> post("/v1/residents/#{id}/presence/follows") |> json_response(200)

    assert ctx.witness
           |> post("/v1/residents/#{id}/presence/accounts/seven/exclude", %{
             reason: "testing the mask"
           })
           |> response(204)

    assert ctx.witness
           |> post("/v1/residents/#{id}/presence/accounts/seven/include", %{note: "back in"})
           |> response(204)

    {:ok, %{reads: [r]}} =
      Xenia.draw_presence(id, "2026-11-15", Oneiroi.Actor.new(:job, "xenia_presence"))

    {:ok, _} = Xenia.presence_read(id, r.item, ctx.her)
    {:ok, n} = Xenia.stage_interaction(id, %{item: r.item, kind: "like"}, ctx.her)

    assert %{
             "settings" => %{"enabled" => true},
             "interactions" => [
               %{"number" => ^n, "state" => "staged", "read" => %{"title" => "The Garden"}}
             ]
           } =
             ctx.witness |> get("/v1/residents/#{id}/presence") |> json_response(200)

    # Tokens reach only the adapter paths: a brain token none of it, a reader no decision.
    assert ctx.brain |> bearer() |> get("/v1/residents/#{id}/presence") |> json_response(401)

    assert ctx.reader
           |> bearer()
           |> post("/v1/residents/#{id}/presence/interactions/#{n}/decision", %{
             decision: "approve"
           })
           |> json_response(401)

    assert ctx.witness
           |> post("/v1/residents/#{id}/presence/interactions/#{n}/decision", %{
             decision: "approve"
           })
           |> response(204)

    Clock.Fake.advance(360 * 60 + 1)

    assert %{"presence" => [%{"number" => ^n}]} =
             ctx.reader |> bearer() |> get("/v1/residents/#{id}/waiting") |> json_response(200)

    assert [
             %{
               "number" => ^n,
               "action" => "like",
               "target" => "post",
               "id" => 11,
               "host" => "https://seven.substack.com"
             }
           ] =
             ctx.reader
             |> bearer()
             |> get("/v1/residents/#{id}/reader/presence")
             |> json_response(200)

    assert ctx.reader
           |> bearer()
           |> post("/v1/residents/#{id}/reader/presence/#{n}/sent", %{
             url: "https://seven.substack.com/p/the-garden"
           })
           |> response(204)

    assert %{"presence" => []} =
             ctx.reader |> bearer() |> get("/v1/residents/#{id}/waiting") |> json_response(200)
  end
end
