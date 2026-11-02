defmodule OneiroiWeb.ConversationsApartTest do
  @moduledoc """
  The Oneiroi chat and the Claude Code conversations, apart (kumbukumbu
  #40 to #42, brain #44): an adapter's token opens a conversation of its
  own, kind `adapter`, called by its folder's base name; the witness's
  list names each and says which takes a message; each knows where it
  is and which others are open, and none carries another's words; and a
  memory tool's call lands on the turn it names, so two sessions open at
  once keep their bookmarks apart.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    actor = Actor.new(:witness, account.id)
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    {:ok, token} = AgathosDaimon.register_adapter(resident.id, "laptop", "brain", actor)
    Model.clear()
    on_exit(fn -> Model.clear(for: resident.id) end)

    witness =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, id: resident.id, account: account, actor: actor, token: token, witness: witness}
  end

  defp adapter(ctx), do: put_req_header(build_conn(), "authorization", "Bearer " <> ctx.token)

  # As the plugin opens one: `main` in the body, which the server does
  # not read for an adapter's token, and the folder as the hook has it.
  defp open(ctx, cwd) do
    %{"key" => key} =
      ctx
      |> adapter()
      |> post("/v1/residents/#{ctx.id}/sessions", %{
        kind: "main",
        runtime: "claude-code",
        label: cwd
      })
      |> json_response(201)

    key
  end

  defp start(ctx, key, text) do
    ctx
    |> adapter()
    |> post("/v1/residents/#{ctx.id}/turn-start", %{
      session_key: key,
      text: text,
      runtime: "claude-code"
    })
    |> json_response(201)
  end

  defp capture(ctx, key, ref, words) do
    ctx
    |> adapter()
    |> post("/v1/residents/#{ctx.id}/turns", %{
      session_key: key,
      turn_ref: ref,
      started_at: DateTime.to_iso8601(Clock.now()),
      messages: [
        %{role: "user", content: words},
        %{role: "assistant", content: "about " <> words}
      ]
    })
    |> json_response(201)
  end

  defp call(ctx, tool, arguments) do
    %{"result" => result} =
      ctx
      |> adapter()
      |> post("/mcp", %{
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: %{name: tool, arguments: arguments}
      })
      |> json_response(200)

    result
  end

  test "an adapter's conversation is its own: kind adapter, the folder's base name, listed apart and read only",
       ctx do
    %{"key" => chat} =
      ctx.witness
      |> post("/v1/residents/#{ctx.id}/sessions", %{kind: "main"})
      |> json_response(201)

    Clock.Fake.advance(60)
    claude = open(ctx, "/home/allen/work/Oneiroi")

    # The witness's chat is still the brain's, however new the other is.
    assert %{"key" => ^chat} =
             ctx.witness
             |> post("/v1/residents/#{ctx.id}/sessions", %{kind: "main"})
             |> json_response(201)

    assert {:ok, %{kind: "adapter", adapter: "laptop", label: "Oneiroi", runtime: "claude-code"},
            []} = Kumbukumbu.transcript({:resident, ctx.id}, claude)

    # Each turn's drew-on count rides the transcript, so a reply read
    # here opens the same inspector a reply just sent does.
    Clock.Fake.advance(60)
    %{"turn_ref" => ref, "drew_on" => drew_on} = start(ctx, claude, "look at the tests")
    capture(ctx, claude, ref, "look at the tests")

    rows = ctx.witness |> get("/v1/residents/#{ctx.id}/sessions") |> json_response(200)

    assert [
             %{
               "key" => ^claude,
               "kind" => "adapter",
               "title" => "Claude Code · Oneiroi",
               "place" => "Oneiroi",
               "writable" => false
             },
             %{"key" => ^chat, "title" => "Oneiroi chat", "place" => nil, "writable" => true}
           ] = rows

    refute inspect(rows) =~ "/home/allen"

    assert %{"session" => %{"writable" => false}, "drew_on" => %{^ref => ^drew_on}} =
             ctx.witness
             |> get("/v1/residents/#{ctx.id}/sessions/#{claude}")
             |> json_response(200)

    assert [_ | _] =
             ctx.witness
             |> get("/v1/residents/#{ctx.id}/turns/#{ref}/context")
             |> json_response(200)

    # The witness replies in Claude Code, not here: the platform's brain
    # never answers in an adapter's conversation.
    assert %{"error" => %{"kind" => "read_only"}} =
             ctx.witness
             |> post("/v1/residents/#{ctx.id}/sessions/#{claude}/turns", %{text: "hello"})
             |> json_response(409)

    # A client cannot open the adapter's kind for itself.
    assert ctx.witness
           |> post("/v1/residents/#{ctx.id}/sessions", %{kind: "adapter"})
           |> json_response(422)
  end

  test "each conversation is told where it is and what else is open, by folder base name alone, and carries no other's words",
       ctx do
    {:ok, chat} = Kumbukumbu.main_session(ctx.id, ctx.account.id, ctx.actor)
    Model.reply("Hello.", for: ctx.id)
    {:ok, _turn} = Oneiroi.Brain.turn(ctx.id, chat, "good morning", ctx.actor)

    Clock.Fake.advance(120)
    a = open(ctx, "/Users/allen/src/catapult")
    %{"turn_ref" => a_ref} = start(ctx, a, "first in catapult")
    capture(ctx, a, a_ref, "CATAPULT-ONLY words about the build")

    Clock.Fake.advance(60)
    b = open(ctx, "/Users/allen/src/Oneiroi")
    c = open(ctx, "/Users/allen/src/Oneiroi")
    %{"turn_ref" => b_ref, "text" => b_text} = start(ctx, b, "and here")

    assert b_text =~ "This conversation is in Claude Code, in the folder Oneiroi."
    assert b_text =~ "Your Oneiroi chat with your witness is a separate conversation"
    assert b_text =~ "your memory is one and the same across both"
    assert b_text =~ "your Oneiroi chat (last spoken in 3 minutes ago)"
    assert b_text =~ "Claude Code in the folder catapult (last spoken in a minute ago)"

    assert b_text =~
             "Claude Code in the folder Oneiroi, another conversation in this same folder (last spoken in under a minute ago)"

    assert b_text =~ "This turn is `#{b_ref}`."
    refute b_text =~ "/Users/allen"
    refute b_text =~ "CATAPULT-ONLY"
    _ = c

    # The Oneiroi chat names the open Claude Code conversations and
    # carries none of their words: its history is its own session's.
    test = self()

    Model.script(
      fn request ->
        send(test, {:request, request})
        {:ok, "Morning."}
      end,
      for: ctx.id
    )

    {:ok, %{turn_ref: chat_ref}} =
      Oneiroi.Brain.turn(ctx.id, chat, "what are you up to?", ctx.actor)

    assert_receive {:request, request}
    sent = Enum.map_join(request.messages, "\n", &(&1.content || ""))

    assert sent =~ "Besides this chat with your witness, you are in other conversations right now"
    assert sent =~ "Claude Code in the folder Oneiroi (a turn in flight)"
    assert sent =~ "Claude Code in the folder catapult"
    assert sent =~ "good morning"
    refute sent =~ "CATAPULT-ONLY"
    refute sent =~ "first in catapult"
    refute sent =~ "/Users/allen"

    assert "where" in Enum.map(
             Kumbukumbu.injections({:account, ctx.account.id}, chat_ref),
             & &1.label
           )
  end

  test "two sessions open at once keep their bookmarks apart: a call lands on the turn it names, and says where it went when it names none",
       ctx do
    a = open(ctx, "/w/catapult")
    Clock.Fake.advance(1)
    b = open(ctx, "/w/Oneiroi")

    # Interleaved: A's turn starts, then B's, so B's is the newest open
    # turn while A's is still in flight.
    %{"turn_ref" => a_ref} = start(ctx, a, "in catapult")
    Clock.Fake.advance(1)
    %{"turn_ref" => b_ref} = start(ctx, b, "in Oneiroi")

    assert %{"content" => [%{"text" => "Bookmarked as #1."}], "_meta" => meta} =
             call(ctx, "bookmark_add", %{line: "the catapult build", turn: a_ref})

    assert %{"oneiroi/turn" => %{"ref" => ^a_ref, "rule" => "named"}} = meta

    assert %{"content" => [%{"text" => "Bookmarked as #2."}]} =
             call(ctx, "bookmark_add", %{line: "the Oneiroi tests", turn: b_ref})

    # Named nothing: the newest open turn, and the answer says where.
    assert %{"content" => [%{"text" => text}], "_meta" => %{"oneiroi/turn" => newest}} =
             call(ctx, "bookmark_add", %{line: "unnamed"})

    assert text =~ "Bookmarked as #3."
    assert text =~ "No turn was named, so this went to the conversation in Oneiroi."
    assert newest == %{"ref" => b_ref, "rule" => "newest"}

    # A read says nothing of it.
    refute call(ctx, "bookmark_list", %{})["content"] |> hd() |> Map.get("text") =~ "was named"

    assert [
             %{number: 1, session_key: ^a, anchor_ref: ^a_ref},
             %{number: 2, session_key: ^b, anchor_ref: ^b_ref},
             %{number: 3, session_key: ^b, anchor_ref: ^b_ref}
           ] = ctx.id |> Kumbukumbu.bookmarks() |> Enum.sort_by(& &1.number)

    # A turn already captured is not open: naming it falls back too.
    capture(ctx, a, a_ref, "in catapult")

    assert %{"_meta" => %{"oneiroi/turn" => %{"ref" => ^b_ref, "rule" => "newest"}}} =
             call(ctx, "bookmark_add", %{line: "late", turn: a_ref})

    # The tools say they take it.
    %{"result" => %{"tools" => tools}} =
      ctx
      |> adapter()
      |> post("/mcp", %{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> json_response(200)

    assert Enum.all?(tools, &Map.has_key?(&1["inputSchema"]["properties"], "turn"))
    refute Enum.any?(tools, &("turn" in (&1["inputSchema"]["required"] || [])))
  end
end
