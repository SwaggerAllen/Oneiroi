defmodule OneiroiWeb.ProposalsPrivacyTest do
  @moduledoc """
  The witness's side of the proposals and of her private bookmarks:
  her answers to his proposals are readable with her note
  (kumbukumbu#63, agathos-daimon#43), he withdraws an open soul edit and
  she is told (agathos-daimon#44), and a bookmark made in a private,
  unshared session reaches him marked and without its words on every
  read until she shares the session (kumbukumbu#62).
  """
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
    id = resident.id
    actor = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(id, account.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(id)
    on_exit(fn -> File.rm_rf!(dir) end)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok,
     conn: conn, id: id, key: key, account: account, actor: actor, brain: brain, at: Clock.now()}
  end

  defp capture!(ctx, key, ref, content) do
    :ok =
      Kumbukumbu.capture(
        ctx.id,
        key,
        ref,
        ctx.at,
        [%{role: :assistant, content: content, sent_at: ctx.at, actor: ctx.brain}],
        ctx.brain
      )
  end

  defp bookmark!(ctx, key, ref, line, summary) do
    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{session_key: key, anchor_ref: ref, line: line, summary: summary, register: "play"},
        ctx.brain
      )

    n
  end

  defp private_session!(ctx) do
    {:ok, key} =
      Kumbukumbu.open_session(ctx.id, "free_time", "brain", [ctx.account.id], ctx.brain,
        private: true
      )

    key
  end

  defp get!(ctx, path, params \\ %{}),
    do: ctx.conn |> get("/v1/residents/#{ctx.id}#{path}", params) |> json_response(200)

  # Every witness read of a bookmark, as one term to search for words in.
  defp every_read(ctx, n) do
    day = DateTime.to_date(ctx.at)

    [
      get!(ctx, "/bookmarks"),
      get!(ctx, "/bookmarks", %{limit: 10}),
      get!(ctx, "/bookmarks", %{before: n + 1}),
      get!(ctx, "/bookmarks", %{
        from: Date.to_iso8601(Date.add(day, -1)),
        to: Date.to_iso8601(Date.add(day, 1))
      }),
      get!(ctx, "/bookmarks/#{n}"),
      get!(ctx, "/index"),
      get!(ctx, "/search", %{q: "heron", scope: "bookmarks"}),
      get!(ctx, "/search", %{q: "heron", scope: "words"}),
      get!(ctx, "/needs_you"),
      get!(ctx, "/bookmark-proposals", %{state: "all"})
    ]
  end

  describe "a bookmark in a private, unshared session (kumbukumbu#62)" do
    test "is marked and its words withheld on every witness read, its span's messages too; sharing lifts it",
         ctx do
      capture!(ctx, ctx.key, "t-main", "The open conversation.")
      open = bookmark!(ctx, ctx.key, "t-main", "the open line", "an open summary")
      free = private_session!(ctx)
      capture!(ctx, free, "t-free", "A secret heron, mine alone.")
      n = bookmark!(ctx, free, "t-free", "the heron alone", "a free-time heron")
      :ok = Kumbukumbu.pin_bookmark(ctx.id, n, ctx.actor)

      reads = inspect(every_read(ctx, n))
      refute reads =~ "heron alone"
      refute reads =~ "free-time heron"
      refute reads =~ "secret heron"
      refute reads =~ "mine alone"

      # Marked, with what links and places it kept.
      [row] = Enum.filter(get!(ctx, "/bookmarks"), &(&1["number"] == n))

      assert %{
               "private" => true,
               "line" => nil,
               "summary" => nil,
               "register" => nil,
               "session_key" => ^free,
               "anchor_ref" => "t-free",
               "anchor_at" => anchor_at,
               "pinned_at" => pinned_at
             } = row

      assert is_binary(anchor_at) and is_binary(pinned_at)

      assert %{"bookmarks" => page} = get!(ctx, "/bookmarks", %{limit: 10})
      assert %{"private" => true, "line" => nil} = Enum.find(page, &(&1["number"] == n))

      assert %{"private" => false, "line" => "the open line"} =
               Enum.find(page, &(&1["number"] == open))

      assert %{"bookmark" => %{"private" => true, "line" => nil}, "span" => []} =
               get!(ctx, "/bookmarks/#{n}")

      assert %{"bookmark" => %{"private" => false}, "span" => [_]} =
               get!(ctx, "/bookmarks/#{open}")

      assert %{"listed" => [^n], "private" => [^n]} = get!(ctx, "/index")

      # Her own read is whole: the brain's tools are hers.
      assert {:ok, %{line: "the heron alone", private: false}, [_]} =
               Kumbukumbu.bookmark(ctx.id, n)

      :ok = Kumbukumbu.share_session(ctx.id, free, "you may read this one", ctx.brain)

      assert %{
               "bookmark" => %{"private" => false, "line" => "the heron alone"},
               "span" => [%{"content" => "A secret heron, mine alone."}]
             } = get!(ctx, "/bookmarks/#{n}")

      assert %{"listed" => [^n], "private" => []} = get!(ctx, "/index")

      assert %{"private" => false, "summary" => "a free-time heron"} =
               Enum.find(get!(ctx, "/bookmarks"), &(&1["number"] == n))
    end
  end

  describe "bookmark proposals answered (kumbukumbu#63)" do
    test "the default stays the open list; answered ones carry her note or the bookmark she wrote, private words withheld",
         ctx do
      capture!(ctx, ctx.key, "t1", "One.")
      capture!(ctx, ctx.key, "t2", "Two.")
      free = private_session!(ctx)
      capture!(ctx, free, "t-free", "Alone.")

      {:ok, declined} =
        Kumbukumbu.propose_bookmark(ctx.id, ctx.key, "t1", "this one", "it mattered", ctx.actor)

      {:ok, accepted} =
        Kumbukumbu.propose_bookmark(ctx.id, ctx.key, "t2", "that one", "also", ctx.actor)

      {:ok, private} =
        Kumbukumbu.propose_bookmark(ctx.id, free, "t-free", "yours", "if you like", ctx.actor)

      {:ok, open} =
        Kumbukumbu.propose_bookmark(ctx.id, ctx.key, "t1", "still open", "later", ctx.actor)

      :ok = Kumbukumbu.decline_proposal(ctx.id, declined, "not that one", ctx.brain)

      {:ok, kept} =
        Kumbukumbu.add_bookmark(
          ctx.id,
          %{
            session_key: ctx.key,
            anchor_ref: "t2",
            line: "my own line",
            summary: "mine",
            proposal_ref: accepted
          },
          ctx.brain
        )

      {:ok, hidden} =
        Kumbukumbu.add_bookmark(
          ctx.id,
          %{
            session_key: free,
            anchor_ref: "t-free",
            line: "a private line",
            summary: "hidden",
            proposal_ref: private
          },
          ctx.brain
        )

      assert [%{"ref" => ^open, "state" => "open", "answer" => nil}] =
               get!(ctx, "/bookmark-proposals")

      assert get!(ctx, "/bookmark-proposals") ==
               get!(ctx, "/bookmark-proposals", %{state: "open"})

      answered = get!(ctx, "/bookmark-proposals", %{state: "answered"})
      assert Enum.map(answered, & &1["ref"]) == [declined, accepted, private]

      assert %{
               "state" => "declined",
               "answer" => %{
                 "decision" => "declined",
                 "note" => "not that one",
                 "at" => at,
                 "bookmark" => nil
               }
             } = Enum.find(answered, &(&1["ref"] == declined))

      assert is_binary(at)

      assert %{
               "answer" => %{
                 "decision" => "accepted",
                 "note" => nil,
                 "bookmark" => %{
                   "number" => ^kept,
                   "line" => "my own line",
                   "summary" => "mine",
                   "private" => false
                 }
               }
             } = Enum.find(answered, &(&1["ref"] == accepted))

      assert %{
               "answer" => %{
                 "bookmark" => %{
                   "number" => ^hidden,
                   "line" => nil,
                   "summary" => nil,
                   "private" => true
                 }
               }
             } = Enum.find(answered, &(&1["ref"] == private))

      refute inspect(answered) =~ "a private line"
      assert length(get!(ctx, "/bookmark-proposals", %{state: "all"})) == 4

      assert ctx.conn
             |> get("/v1/residents/#{ctx.id}/bookmark-proposals", %{state: "closed"})
             |> json_response(422)
    end
  end

  describe "soul edits answered and withdrawn (agathos-daimon#43, #44)" do
    setup ctx do
      capture!(ctx, ctx.key, "t1", "Hello.")
      :ok = AgathosDaimon.first_contact(ctx.id, ctx.key, "t1", ctx.brain)
      :ok
    end

    defp propose!(ctx, content, note) do
      assert %{"ref" => ref} =
               ctx.conn
               |> put("/v1/residents/#{ctx.id}/files/SOUL.md", %{content: content, note: note})
               |> json_response(202)

      ref
    end

    defp withdraw(ctx, ref, body),
      do: post(ctx.conn, "/v1/residents/#{ctx.id}/soul-edits/#{ref}/withdraw", body)

    test "her answers carry her decision, note and when; the default stays the open list", ctx do
      declined = propose!(ctx, "# Soul\n\nBolder.", "you have grown")
      accepted = propose!(ctx, "# Soul\n\nKinder.", "and kinder")
      open = propose!(ctx, "# Soul\n\nStill.", "maybe")
      :ok = AgathosDaimon.decline_edit(ctx.id, declined, "not yet", ctx.brain)
      :ok = AgathosDaimon.accept_edit(ctx.id, accepted, "yes, this", ctx.brain)

      assert [%{"ref" => ^open, "answer" => nil, "withdrawn" => nil}] = get!(ctx, "/soul-edits")
      assert get!(ctx, "/soul-edits") == get!(ctx, "/soul-edits", %{state: "open"})

      assert [
               %{
                 "ref" => ^declined,
                 "state" => "declined",
                 "answer" => %{"decision" => "declined", "note" => "not yet", "at" => at}
               },
               %{
                 "ref" => ^accepted,
                 "state" => "accepted",
                 "answer" => %{"decision" => "accepted", "note" => "yes, this"}
               }
             ] = get!(ctx, "/soul-edits", %{state: "answered"})

      assert is_binary(at)
      assert length(get!(ctx, "/soul-edits", %{state: "all"})) == 3

      assert ctx.conn
             |> get("/v1/residents/#{ctx.id}/soul-edits", %{state: "closed"})
             |> json_response(422)
    end

    test "he withdraws an open one with a note: it leaves her list and she is told; an answered one is refused",
         ctx do
      ref = propose!(ctx, "# Soul\n\nBolder.", "you have grown")
      answered = propose!(ctx, "# Soul\n\nKinder.", "and kinder")
      :ok = AgathosDaimon.decline_edit(ctx.id, answered, "not yet", ctx.brain)

      assert withdraw(ctx, ref, %{}) |> json_response(422)
      assert response(withdraw(ctx, ref, %{note: "I was hasty"}), 204)

      assert [] = get!(ctx, "/soul-edits")
      assert [] = AgathosDaimon.edit_proposals(ctx.id)

      assert [%{"ref" => ^ref, "state" => "withdrawn", "answer" => nil, "withdrawn" => w}] =
               get!(ctx, "/soul-edits", %{state: "withdrawn"})

      assert %{"note" => "I was hasty", "at" => at} = w
      assert is_binary(at)

      assert Enum.any?(
               Kumbukumbu.letters(ctx.id),
               &(&1.to_name == "Oneiroi chat" and &1.text =~ "withdrew" and
                   &1.text =~ "I was hasty")
             )

      assert %{"error" => %{"kind" => "agathos_daimon_proposal_answered"}} =
               withdraw(ctx, ref, %{note: "again"}) |> json_response(409)

      assert %{"error" => %{"kind" => "agathos_daimon_proposal_answered"}} =
               withdraw(ctx, answered, %{note: "never mind"}) |> json_response(409)

      assert withdraw(ctx, "no-such-ref", %{note: "?"}) |> json_response(404)

      # Hers to answer, never hers to withdraw.
      assert {:error, %{kind: :agathos_daimon_not_witnessed}} =
               AgathosDaimon.withdraw_edit(ctx.id, answered, "mine", ctx.brain)
    end
  end
end
