defmodule OneiroiWeb.NeedsYouRoutesTest do
  @moduledoc """
  brain#65 (spec §5's `needs_you`): everything waiting on the witness's
  decision, from every system, one list oldest first, each naming where
  it is decided; an entry past two days is marked long, and nothing
  else happens to it. A replaced draft, a sent reply, an answered ask
  and an open work item wait on nobody.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Sunna
  alias Oneiroi.Xenia

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Actor.new(:witness, account.id)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", witness)
    {:ok, id: resident.id, token: token, me: witness, lily: Actor.new(:resident, resident.id)}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)

  defp read(ctx),
    do: ctx.token |> as() |> get("/v1/residents/#{ctx.id}/needs_you") |> json_response(200)

  test "one list from every system, oldest first, the long ones marked and nothing done", ctx do
    assert [] = read(ctx)
    new = %{platform: "email", account: "lily@example.com", to: "jack@example.com"}

    {:ok, 1} = Xenia.draft_reply(ctx.id, Map.put(new, :text, "First go."), ctx.lily)
    Clock.Fake.advance(3600)
    {:ok, 1} = AgathosDaimon.ask(ctx.id, "act", "Post the essay", "It is done.", ctx.lily)
    Clock.Fake.advance(3600)

    {:ok, 2} =
      Xenia.draft_reply(ctx.id, Map.merge(new, %{text: "Second.", supersedes: 1}), ctx.lily)

    {:ok, 1} = Sunna.work_add(ctx.id, "Re-stage the Jack letter", "in the queue", ctx.lily)
    {:ok, 2} = Sunna.work_add(ctx.id, "Something open", "done", ctx.lily)
    # Blocked on other work is the queue's, never his (sunna#42).
    :ok = Sunna.work_move(ctx.id, 1, "blocked", "2", "waiting on it", ctx.lily)

    assert [
             %{"kind" => "ask", "ref" => 1, "screen" => "inbox", "long" => false},
             %{
               "kind" => "reply_to_approve",
               "ref" => 2,
               "about" => %{"to" => "jack@example.com", "account" => "lily@example.com"}
             }
           ] = read(ctx)

    :ok = Xenia.decide_reply(ctx.id, 2, true, "Good.", ctx.me)
    Clock.Fake.advance(48 * 3600)

    assert [
             %{"kind" => "ask", "long" => true},
             %{"kind" => "reply_to_send", "ref" => 2, "long" => true}
           ] = read(ctx)

    # The mark is all: the reply is still approved and unsent, the ask open.
    assert [%{state: "approved"} | _] = Xenia.replies(ctx.id, nil)
    assert [%{decision: nil}] = AgathosDaimon.asks(ctx.id)
  end
end
