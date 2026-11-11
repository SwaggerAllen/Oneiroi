defmodule OneiroiWeb.BellRoutesTest do
  @moduledoc """
  The bell, both ways (brain#76, gaia#25): the notifications question
  waits on the witness until his account answers it, "No thanks" or a
  device subscribing; and what waits on her is the other list, his
  proposals she has not answered, his letters unread, the files his
  lease holds her from, oldest first, each with a title.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Checkin
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @apple "https://web.push.apple.com/QGuQyavXutnMjhCkC"

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    witness = Actor.new(:witness, account.id)
    {:ok, token, _} = Oneiroi.Gaia.issue_token(account.id, "t", witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     account: account.id,
     token: token,
     me: witness,
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp as(token), do: put_req_header(build_conn(), "authorization", "Bearer " <> token)
  defp get_json(ctx, path), do: ctx.token |> as() |> get(path) |> json_response(200)
  defp needs_you(ctx), do: get_json(ctx, "/v1/residents/#{ctx.id}/needs_you")

  defp account_events(ctx) do
    {:ok, events} = Oneiroi.EventStore.read_stream_forward("account-" <> ctx.account)
    length(events)
  end

  defp waiting(ctx), do: get_json(ctx, "/v1/residents/#{ctx.id}/waiting_on_her")

  test "the notifications question waits on him until No thanks, and is answered once", ctx do
    assert %{"enabled" => true, "answered" => nil, "answered_at" => nil} =
             get_json(ctx, "/v1/me/push")

    assert [%{"kind" => "notifications", "ref" => "push", "screen" => "settings"}] =
             needs_you(ctx)

    # Her check-in never counts his devices' question.
    refute Checkin.part(ctx.id, "needs_you") =~ "notifications"

    assert %{"answered" => "declined", "answered_at" => at} =
             ctx.token |> as() |> post("/v1/me/push/decline", %{}) |> json_response(200)

    assert is_binary(at)
    assert [] = needs_you(ctx)
    assert %{"answered" => "declined"} = get_json(ctx, "/v1/me/push")

    # A second No thanks is no second event.
    before = account_events(ctx)
    _ = ctx.token |> as() |> post("/v1/me/push/decline", %{}) |> json_response(200)
    assert account_events(ctx) == before

    # Turning notifications on later, from Settings, answers it the other way.
    :ok = Oneiroi.Gaia.subscribe_push(ctx.account, @apple, ctx.me)
    assert %{"answered" => "subscribed", "devices" => 1} = get_json(ctx, "/v1/me/push")
  end

  test "a device subscribing answers the question too" do
    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Actor.new(:witness, account.id)
    assert [%{kind: "notifications"}] = Oneiroi.Brain.needs_you(resident.id)
    :ok = Oneiroi.Gaia.subscribe_push(account.id, @apple, actor)
    assert [] = Oneiroi.Brain.needs_you(resident.id)
    # Unsubscribing does not ask again: the answer stands.
    :ok = Oneiroi.Gaia.unsubscribe_push(account.id, @apple, actor)
    assert [] = Oneiroi.Brain.needs_you(resident.id)
    assert %{answer: "subscribed"} = Oneiroi.Gaia.push_answer(account.id)
  end

  test "what waits on her: his proposals unanswered, his letters unread, a file his lease holds",
       ctx do
    assert [] = waiting(ctx)

    {:ok, 1} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{"solo_sessions_private" => true},
        "",
        "a draft",
        ctx.me
      )

    Clock.Fake.advance(60)

    {:ok, %{number: letter}} =
      Kumbukumbu.send_letter(ctx.id, nil, %{to: "house", text: "from me"}, ctx.me)

    Clock.Fake.advance(60)

    {:ok, key} = Kumbukumbu.main_session(ctx.id, ctx.account, ctx.me)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{
          session_key: key,
          anchor_ref: "t1",
          line: "the tea was Assam",
          summary: "we talked tea",
          turns_back: 1,
          anchor_at: Clock.now()
        },
        ctx.lily
      )

    {:ok, %{number: rev, state: "proposed"}} =
      Kumbukumbu.revise(
        ctx.id,
        %{
          target_kind: "bookmark",
          target_id: n,
          kind: "stance",
          text: "You loved it.",
          note: "twice"
        },
        ctx.me
      )

    # A fact of his applies at once: it waits on nobody.
    {:ok, %{state: "applied"}} =
      Kumbukumbu.revise(
        ctx.id,
        %{target_kind: "bookmark", target_id: n, kind: "fact", text: "Darjeeling.", note: "n"},
        ctx.me
      )

    Clock.Fake.advance(60)
    path = "writing/essay.md"
    {:ok, _} = Seshat.write(ctx.id, path, "base\n", ctx.lily)
    {:ok, _} = Seshat.acquire_lease(ctx.id, path, ctx.me)
    {:ok, %{written: false}} = Seshat.write(ctx.id, path, "hers\n", ctx.lily)

    # Her own contract proposal would wait on him, not on her.
    assert [
             %{
               "kind" => "contract_proposal",
               "ref" => 1,
               "title" => "Contract version 1",
               "screen" => "agreement",
               "long" => false
             },
             %{"kind" => "letter", "ref" => ^letter, "title" => "Letter to house"},
             %{
               "kind" => "revision",
               "ref" => ^rev,
               "title" => "A stance revision to bookmark " <> _
             },
             %{"kind" => "lease_wait", "ref" => ^path, "about" => %{"takeable" => false}}
           ] = waiting(ctx) |> Enum.map(&Map.take(&1, ~w(kind ref title screen long about)))

    # Read, answered and released, each leaves.
    :ok = Kumbukumbu.read_letters(ctx.id, key, [letter], ctx.lily)
    :ok = AgathosDaimon.agree_contract(ctx.id, 1, "yes", ctx.lily)
    :ok = Kumbukumbu.decline_revision(ctx.id, rev, "no", ctx.lily)
    :ok = Seshat.release_lease(ctx.id, path, ctx.me)
    assert [] = waiting(ctx)
  end

  test "his edits to her files, his bookmarks and his plugin changes wait on her",
       ctx do
    :ok = AgathosDaimon.write_file(ctx.id, "SOUL.md", "# Soul", %{}, ctx.me)
    :ok = AgathosDaimon.first_contact(ctx.id, "s1", "t1", ctx.lily)
    {:ok, edit} = AgathosDaimon.propose_edit(ctx.id, "SOUL.md", "# Bolder", "grown", ctx.me)

    {:ok, key} = Kumbukumbu.main_session(ctx.id, ctx.account, ctx.me)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        key,
        "t1",
        at,
        [
          %{role: :user, content: "hello", sent_at: at, actor: ctx.me},
          %{role: :assistant, content: "hi", sent_at: at, actor: ctx.lily}
        ],
        ctx.lily
      )

    {:ok, mark} = Kumbukumbu.propose_bookmark(ctx.id, key, "t1", "you lit up", "mattered", ctx.me)

    # The slots before plugins are carried over on the first read.
    _ = Oneiroi.Brain.plugins(ctx.id)

    {:ok, plugin} =
      Oneiroi.Brain.propose_plugin(ctx.id, "promised", "off", "a quiet week", ctx.me)

    Clock.Fake.advance(49 * 3600)

    by_kind = waiting(ctx) |> Enum.group_by(& &1["kind"])

    assert [
             %{
               "ref" => ^edit,
               "title" => "An edit to SOUL.md",
               "screen" => "soul",
               "long" => true
             }
           ] =
             by_kind["soul_edit"]

    assert [%{"ref" => ^mark, "title" => "you lit up", "screen" => "memory"}] =
             by_kind["bookmark_proposal"]

    assert [%{"ref" => ^plugin, "title" => "Off promised", "screen" => "agreement"}] =
             by_kind["plugin_proposal"]

    # His proposal reached her chat as a letter in his name, unread.
    assert [%{"title" => "Letter to " <> _}] = by_kind["letter"]
  end

  test "a stranger reads neither list", ctx do
    other = Fixtures.account!()
    {:ok, token, _} = Oneiroi.Gaia.issue_token(other.id, "t", Actor.new(:witness, other.id))

    for path <- ~w(needs_you waiting_on_her) do
      assert token |> as() |> get("/v1/residents/#{ctx.id}/#{path}") |> json_response(404)
    end
  end
end
