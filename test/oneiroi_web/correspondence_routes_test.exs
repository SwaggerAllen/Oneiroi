defmodule OneiroiWeb.CorrespondenceRoutesTest do
  @moduledoc "Correspondence over HTTP (xenia #11): the reader's token delivers, reads approved replies and marks one sent, and nothing more; a brain token reaches none of it; the witness reads, blocks and decides replies; a stranger nothing."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Xenia

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Oneiroi.Actor.new(:witness, account.id)
    {:ok, reader} = AgathosDaimon.register_adapter(resident.id, "scrape", "reader", actor)
    {:ok, brain} = AgathosDaimon.register_adapter(resident.id, "claude-code", "brain", actor)

    {:ok,
     id: resident.id,
     account: account,
     reader: reader,
     brain: brain,
     lily: Oneiroi.Actor.new(:resident, resident.id),
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

  @message %{
    platform: "substack",
    account: "lily",
    external_id: "dm-1",
    sender: "max",
    sender_name: "Max",
    verified: true,
    text: "A letter for Lily.",
    sent_at: "2026-11-02T18:00:00Z"
  }

  test "the reader delivers and sends, the witness reads, blocks and approves, a brain token reaches none of it",
       ctx do
    id = ctx.id

    assert [%{"number" => 1}] =
             ctx.reader
             |> bearer()
             |> post("/v1/residents/#{id}/correspondence", %{messages: [@message]})
             |> json_response(200)

    # The reader reads no messages and blocks nobody.
    assert ctx.reader
           |> bearer()
           |> get("/v1/residents/#{id}/correspondence")
           |> json_response(401)

    assert ctx.reader
           |> bearer()
           |> post("/v1/residents/#{id}/blocks", %{platform: "x", identity: "y", note: "z"})
           |> json_response(401)

    # A brain token, the resident's own, delivers nothing: she does not scrape.
    assert ctx.brain
           |> bearer()
           |> post("/v1/residents/#{id}/correspondence", %{messages: [@message]})
           |> json_response(404)

    assert [%{"number" => 1, "state" => "received", "text" => "A letter for Lily."}] =
             ctx.witness |> get("/v1/residents/#{id}/correspondence") |> json_response(200)

    assert ctx.witness
           |> post("/v1/residents/#{id}/blocks", %{
             platform: "substack",
             identity: "troll",
             name: "Troll",
             note: "Harassment."
           })
           |> response(204)

    assert [%{"identity" => "troll", "blocked_by" => "witness", "note" => "Harassment."}] =
             ctx.witness |> get("/v1/residents/#{id}/blocks") |> json_response(200)

    assert ctx.witness
           |> post("/v1/residents/#{id}/blocks/lift", %{
             platform: "substack",
             identity: "troll",
             note: "Settled."
           })
           |> response(204)

    assert [] = ctx.witness |> get("/v1/residents/#{id}/blocks") |> json_response(200)

    {:ok, 1} = Xenia.draft_reply(id, %{in_reply_to: 1, text: "Dear Max."}, ctx.lily)
    {:ok, 2} = Xenia.draft_reply(id, %{in_reply_to: 1, text: "Not this one."}, ctx.lily)

    # The reader sees approved replies alone.
    assert [] = ctx.reader |> bearer() |> get("/v1/residents/#{id}/replies") |> json_response(200)

    assert ctx.witness
           |> post("/v1/residents/#{id}/replies/1/decision", %{approve: true, note: "Send it."})
           |> response(204)

    assert ctx.witness
           |> post("/v1/residents/#{id}/replies/2/decision", %{approve: false, note: "Too soon."})
           |> response(204)

    assert [%{"number" => 1, "to" => "max", "text" => "Dear Max."}] =
             ctx.reader
             |> bearer()
             |> get("/v1/residents/#{id}/replies?state=declined")
             |> json_response(200)

    # What waits for the reader (kumbukumbu #48): the approved reply to
    # send, by number and platform, and no letters, which are a brain's.
    assert %{"replies" => [%{"number" => 1, "platform" => platform}], "letters" => []} =
             ctx.reader
             |> bearer()
             |> get("/v1/residents/#{id}/waiting?session_key=anything")
             |> json_response(200)

    assert is_binary(platform)

    assert ctx.reader
           |> bearer()
           |> post("/v1/residents/#{id}/replies/1/sent", %{url: "https://substack.com/chat/1"})
           |> response(204)

    # Sent, it waits no more.
    assert %{"replies" => []} =
             ctx.reader |> bearer() |> get("/v1/residents/#{id}/waiting") |> json_response(200)

    assert %{"error" => %{"kind" => "xenia_reply_not_approved"}} =
             ctx.reader
             |> bearer()
             |> post("/v1/residents/#{id}/replies/2/sent", %{})
             |> json_response(422)

    assert [
             %{"state" => "declined", "note" => "Too soon."},
             %{"state" => "sent", "sent_by" => "hands"}
           ] =
             ctx.witness |> get("/v1/residents/#{id}/replies") |> json_response(200)

    # A stranger reads nothing; another resident's reader delivers nothing here.
    stranger = Fixtures.account!()
    assert stranger |> login() |> get("/v1/residents/#{id}/correspondence") |> json_response(404)

    other = Fixtures.resident!(ctx.account)

    {:ok, other_reader} =
      AgathosDaimon.register_adapter(
        other.id,
        "scrape",
        "reader",
        Oneiroi.Actor.new(:witness, ctx.account.id)
      )

    assert other_reader
           |> bearer()
           |> post("/v1/residents/#{id}/correspondence", %{messages: [@message]})
           |> json_response(404)
  end
end
