defmodule Oneiroi.SimaQian.HonchoMemoryTest do
  @moduledoc """
  Honcho's memory of the resident, exported under `honcho/` (sima-qian
  #42, proteus #18): read at the HTTP boundary from a Honcho that
  answers in the deployed server's recorded shapes, written as
  identical bytes from an unchanged Honcho, withheld where a session is
  private, and left as it was when Honcho cannot answer or answers that
  she has no peer.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Proteus.Bridges
  alias Oneiroi.Proteus.Honcho.Fake
  alias Oneiroi.Proteus.Honcho.HTTP
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.HonchoMemory

  defmodule V3 do
    @moduledoc """
    A Honcho on the loopback answering the reads the export makes, held
    to the deployed server's record (`Honcho.Recorded`, read from
    plastic-labs/honcho at the pinned commit, proteus #9): a request the
    server would refuse is its 422, and every answer this Honcho gives
    is checked against the response shapes recorded there, so it cannot
    answer in a shape the server never sends. No bearer is a 401, a
    route it does not answer a 404.
    """
    @behaviour Plug
    import Plug.Conn

    alias Oneiroi.Proteus.Honcho.Recorded

    @impl true
    def init(agent), do: agent

    @impl true
    def call(conn, agent) do
      conn = fetch_query_params(conn)
      {:ok, raw, conn} = read_body(conn)
      state = Agent.get(agent, & &1)
      Agent.update(agent, &Map.update!(&1, :calls, fn calls -> calls ++ [route(conn)] end))

      read = %{
        method: conn.method,
        path: tl(conn.path_info),
        params: conn.query_params,
        body: if(raw == "", do: nil, else: Jason.decode!(raw))
      }

      cond do
        state.down ->
          send_resp(conn, 503, ~s({"detail":"down"}))

        get_req_header(conn, "authorization") == [] ->
          send_resp(conn, 401, ~s({"detail":"Not authenticated"}))

        problem = Recorded.refusal(read) ->
          Agent.update(agent, &Map.update!(&1, :refused, fn r -> r ++ [problem] end))
          send_resp(conn, 422, ~s({"detail":"refused"}))

        true ->
          answer(conn, conn.method, conn.path_info, state)
      end
    end

    defp route(conn), do: {conn.method, Enum.join(conn.path_info, "/"), conn.query_params}

    defp answer(conn, "POST", ["v3", "workspaces", ws, "peers", "list"], s),
      do: page(conn, "Peer", Enum.map(s.peers, &peer(ws, &1)), s)

    defp answer(conn, "GET", ["v3", "workspaces", _ws, "peers", peer, "card"], s) do
      target = conn.query_params["target"] || peer
      json(conn, "PeerCardResponse", %{"peer_card" => Map.get(s.cards, {peer, target})})
    end

    defp answer(conn, "POST", ["v3", "workspaces", _ws, "conclusions", "list"], s),
      do: page(conn, "Conclusion", s.conclusions, s)

    defp answer(conn, "POST", ["v3", "workspaces", ws, "sessions", "list"], s),
      do: page(conn, "Session", Enum.map(s.sessions, &session(ws, &1)), s)

    defp answer(conn, "GET", ["v3", "workspaces", _ws, "sessions", id, "summaries"], s) do
      {short, long} = Map.get(s.summaries, id, {nil, nil})

      json(conn, "SessionSummaries", %{
        "id" => id,
        "short_summary" => short,
        "long_summary" => long
      })
    end

    defp answer(conn, _method, _path, _s), do: send_resp(conn, 404, ~s({"detail":"Not Found"}))

    # The size bound is the record's (1 to 100), checked before this.
    defp page(conn, item, items, s) do
      page = String.to_integer(conn.query_params["page"] || "1")
      size = String.to_integer(conn.query_params["size"] || "50")
      items = if s.reversed, do: Enum.reverse(items), else: items
      total = length(items)

      json(conn, "Page[#{item}]", %{
        "items" => items |> Enum.drop((page - 1) * size) |> Enum.take(size),
        "page" => page,
        "size" => size,
        "total" => total,
        "pages" => div(total + size - 1, size)
      })
    end

    defp peer(ws, id),
      do: %{
        "id" => id,
        "uid" => "u-" <> id,
        "workspace_id" => ws,
        "created_at" => "2026-10-26T12:00:00.123456+00:00",
        "metadata" => %{},
        "configuration" => %{}
      }

    defp session(ws, id),
      do: %{
        "id" => id,
        "uid" => "u-" <> id,
        "is_active" => true,
        "workspace_id" => ws,
        "metadata" => %{},
        "configuration" => %{},
        "created_at" => "2026-10-26T12:00:00.123456+00:00"
      }

    # An answer in a shape the server never sends is this test's bug, not
    # the client's, and fails here rather than passing on a fiction.
    defp json(conn, model, body) do
      if problem = Recorded.answer_problem(model, body), do: raise(problem)
      conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
    end
  end

  setup do
    a = Fixtures.account!()
    r = Fixtures.resident!(a)
    actor = Actor.new(:witness, a.id)
    working = Backup.dir(r.id)
    on_exit(fn -> File.rm_rf!(working) end)
    on_exit(fn -> Fake.clear(for: r.id) end)
    {:ok, a: a, r: r, actor: actor, working: working}
  end

  defp conclusion(id, content, observer, observed, attrs \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "content" => content,
        "observer_id" => observer,
        "observed_id" => observed,
        "session_id" => nil,
        "level" => "explicit",
        "source_ids" => [],
        "source_message_ids" => nil,
        "times_derived" => 1,
        "created_at" => "2026-10-26T12:30:00.000000+00:00"
      },
      attrs
    )
  end

  defp summary(content, message),
    do: %{
      "content" => content,
      "message_id" => message,
      "summary_type" => "short",
      "created_at" => "2026-10-26T13:00:00.000000+00:00",
      "token_count" => 12
    }

  defp honcho!(state) do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           Map.merge(
             %{down: false, reversed: false, calls: [], refused: [], summaries: %{}},
             state
           )
         end}
      )

    start_supervised!({Bandit, plug: {V3, agent}, ip: {127, 0, 0, 1}, port: 47_817})
    agent
  end

  test "read at the HTTP boundary and rendered as exact bytes; an unchanged Honcho answering in another order writes the same",
       %{a: a, r: r, actor: actor} do
    :ok = Oneiroi.Proteus.provision(r.id, actor)
    me = "resident-" <> r.id
    you = "witness-" <> a.id

    agent =
      honcho!(%{
        peers: [you, me],
        cards: %{
          {me, me} => ["Steady in the mornings."],
          {me, you} => ["Bakes rye on Sundays.", "Calls #{me} by name."]
        },
        conclusions: [
          conclusion("c3", "Prefers rye.", me, you, %{"session_id" => "main-key"}),
          conclusion("c1", "Asked #{me} to bake.\nTwice.", you, me, %{
            "created_at" => "2026-10-26T12:10:00.000000+00:00"
          }),
          conclusion("c4", "Bakes when uneasy.", me, you, %{
            "level" => "deductive",
            "source_ids" => ["c3", "c2"],
            "created_at" => "2026-10-26T12:40:00.000000+00:00"
          }),
          conclusion("c2", "Spoke of the river.", me, you, %{"session_id" => "quiet-key"})
        ],
        sessions: ["quiet-key", "main-key"],
        summaries: %{
          "main-key" => {summary("They baked.", "m9"), nil},
          "quiet-key" => {summary("Alone by the river.", "m2"), nil}
        }
      })

    assert {:ok, memory} = Bridges.memory(r.id, HTTP)
    files = HonchoMemory.render(memory, r.id, MapSet.new(["quiet-key"]))

    assert Enum.map(files, &elem(&1, 0)) == [
             "honcho/resident/card.md",
             "honcho/resident/conclusions.md",
             "honcho/summaries.md",
             "honcho/witness-#{a.id}/card.md",
             "honcho/witness-#{a.id}/conclusions.md"
           ]

    preamble = """
    What Honcho holds, exported by Oneiroi before each backup commit
    (sima-qian #42): a reading copy, rewritten whole each run, never read
    back and never searched.
    """

    files = Map.new(files)

    assert files["honcho/resident/card.md"] ==
             """
             # The cards resident holds

             #{preamble}
             ## Of itself

             - Steady in the mornings.

             ## Of witness-#{a.id}

             - Bakes rye on Sundays.
             - Calls resident-$self by name.
             """

    assert files["honcho/resident/conclusions.md"] ==
             """
             # What resident has concluded

             #{preamble}
             ## Of witness-#{a.id}

             - `c3` · explicit · 2026-10-26 12:30:00 UTC · session `main-key`
               Prefers rye.
             - `c4` · deductive · 2026-10-26 12:40:00 UTC · from `c2`, `c3`
               Bakes when uneasy.

             1 drawn from a private session is withheld, as the session's words are (spec §6.3).
             """

    assert files["honcho/witness-#{a.id}/card.md"] ==
             """
             # The cards witness-#{a.id} holds

             #{preamble}
             Honcho holds no card under this peer.
             """

    assert files["honcho/witness-#{a.id}/conclusions.md"] ==
             """
             # What witness-#{a.id} has concluded

             #{preamble}
             ## Of resident

             - `c1` · explicit · 2026-10-26 12:10:00 UTC
               Asked resident-$self to bake.
               Twice.
             """

    assert files["honcho/summaries.md"] ==
             """
             # Honcho's summaries of the sessions

             #{preamble}
             ## Session `main-key`

             ### Short, through message `m9`

             They baked.

             ## Session `quiet-key`

             Private: Honcho's summaries of it are withheld, as its words are (spec §6.3).
             """

    refute Enum.any?(Map.values(files), &(&1 =~ r.id))

    # Every list walked as the SDK walks it, every card asked for by pair.
    calls = Agent.get(agent, & &1.calls)

    assert {"POST", "v3/workspaces/#{r.id}/peers/list", %{"page" => "1", "size" => "100"}} in calls

    assert {"GET", "v3/workspaces/#{r.id}/peers/#{me}/card", %{}} in calls
    assert {"GET", "v3/workspaces/#{r.id}/peers/#{me}/card", %{"target" => you}} in calls
    assert {"GET", "v3/workspaces/#{r.id}/sessions/quiet-key/summaries", %{}} in calls

    # The same Honcho, its lists answered in the other order.
    Agent.update(agent, &%{&1 | reversed: true})
    assert {:ok, again} = Bridges.memory(r.id, HTTP)
    assert Map.new(HonchoMemory.render(again, r.id, MapSet.new(["quiet-key"]))) == files
  end

  test "every page of a long list is walked", %{a: a, r: r, actor: actor} do
    :ok = Oneiroi.Proteus.provision(r.id, actor)
    me = "resident-" <> r.id

    many =
      for n <- 1..205,
          do:
            conclusion(
              "c#{String.pad_leading("#{n}", 3, "0")}",
              "fact #{n}",
              me,
              "witness-" <> a.id
            )

    agent = honcho!(%{peers: [me], cards: %{}, conclusions: many, sessions: []})
    assert {:ok, %{conclusions: read}} = Bridges.memory(r.id, HTTP)
    assert length(read) == 205

    pages =
      for {"POST", "v3/workspaces/" <> rest, %{"page" => page}} <- Agent.get(agent, & &1.calls),
          String.ends_with?(rest, "/conclusions/list"),
          do: page

    assert pages == ["1", "2", "3"]
  end

  test "a Honcho that answers 503 is the bridge's sited error, never a partial read", %{
    r: r,
    actor: actor
  } do
    :ok = Oneiroi.Proteus.provision(r.id, actor)

    honcho!(%{peers: ["resident-" <> r.id], cards: %{}, conclusions: [], sessions: [], down: true})

    assert {:error,
            %Oneiroi.Proteus.Error{kind: :proteus_honcho_rejected, details: [status: 503]}} =
             Bridges.memory(r.id, HTTP)
  end

  # ---- the backup's half, over the in-memory Honcho ----

  defp backed_up!(ctx) do
    bare = Path.join(System.tmp_dir!(), "oneiroi-honcho-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    on_exit(fn -> File.rm_rf!(bare) end)
    :ok = Oneiroi.SimaQian.set_remote(ctx.r.id, bare, nil, ctx.actor)
    bare
  end

  defp seed!(%{r: r, a: a, actor: actor}) do
    :ok = Oneiroi.Proteus.provision(r.id, actor)
    me = "resident-" <> r.id
    you = "witness-" <> a.id
    brain = Actor.new(:resident, r.id, "fake/model")

    {:ok, quiet} =
      Kumbukumbu.open_session(r.id, "free_time", "brain", [a.id], brain, private: true)

    Fake.put_card(r.id, me, you, ["Bakes rye."])

    Fake.put_conclusions(r.id, me, you, [
      %{id: "c1", content: "Prefers rye.", created_at: "2026-10-26T12:30:00+00:00"},
      %{
        id: "c2",
        content: "Said it alone.",
        session: quiet,
        created_at: "2026-10-26T12:31:00+00:00"
      }
    ])

    Fake.put_summaries(r.id, quiet, %{content: "Alone.", through: "m1"}, nil)
    :ok = Fake.ensure_session(r.id, quiet, [me])
    quiet
  end

  defp honcho_files(working) do
    working
    |> Path.join("honcho/**/*.md")
    |> Path.wildcard()
    |> Map.new(&{Path.relative_to(&1, working), File.read!(&1)})
  end

  test "the backup writes it under honcho/ in the soul class, withholds the private session's, and an unchanged Honcho commits nothing new",
       ctx do
    bare = backed_up!(ctx)
    quiet = seed!(ctx)
    Clock.Fake.advance(120)

    assert {:ok, %{commits: [{"soul", _}, {"machine", _}]}} =
             Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)

    written = honcho_files(ctx.working)

    assert Map.keys(written) == [
             "honcho/custom-instructions.md",
             "honcho/resident/card.md",
             "honcho/resident/conclusions.md",
             "honcho/summaries.md",
             "honcho/witness-#{ctx.a.id}/card.md",
             "honcho/witness-#{ctx.a.id}/conclusions.md"
           ]

    assert written["honcho/resident/card.md"] =~ "## Of witness-#{ctx.a.id}\n\n- Bakes rye.\n"
    assert written["honcho/resident/conclusions.md"] =~ "Prefers rye."
    refute written["honcho/resident/conclusions.md"] =~ "Said it alone."

    assert written["honcho/resident/conclusions.md"] =~
             "1 drawn from a private session is withheld"

    assert written["honcho/summaries.md"] =~ "## Session `#{quiet}`\n\nPrivate:"
    refute written["honcho/summaries.md"] =~ "Alone."

    {tree, 0} = System.cmd("git", ["ls-tree", "-r", "--name-only", "main"], cd: bare)
    assert tree =~ "honcho/resident/conclusions.md"

    Clock.Fake.advance(120)
    assert {:ok, %{commits: []}} = Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)
    assert honcho_files(ctx.working) == written
  end

  test "a Honcho that cannot answer leaves the last export and fails the run after the rest has landed",
       ctx do
    bare = backed_up!(ctx)
    seed!(ctx)
    Clock.Fake.advance(120)
    assert {:ok, _} = Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)
    before = honcho_files(ctx.working)

    {:ok, _} = Kumbukumbu.main_session(ctx.r.id, ctx.a.id, ctx.actor)
    Fake.fail(:transport, for: ctx.r.id)
    Clock.Fake.advance(120)

    assert {:error,
            %Error{kind: :sima_qian_honcho_unreadable, site: :sima_qian_honcho_memory_unreadable}} =
             Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)

    assert honcho_files(ctx.working) == before

    # The rest landed: the new session's opening is in the pushed export.
    {log, 0} = System.cmd("git", ["log", "-1", "--format=%s", "main"], cd: bare)
    assert log =~ "Records: machine"
    {day, 0} = System.cmd("git", ["show", "main:records/events/2026-10-26.jsonl"], cd: bare)
    assert day =~ "SessionOpened"
  end

  test "a provisioned workspace that answers with no peer is refused, never written empty", ctx do
    backed_up!(ctx)
    seed!(ctx)
    Clock.Fake.advance(120)
    assert {:ok, _} = Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)
    before = honcho_files(ctx.working)

    # Honcho forgets the workspace; the bridge still says it made one.
    Fake.clear(for: ctx.r.id)
    Clock.Fake.advance(120)

    assert {:error, %Error{kind: :sima_qian_honcho_empty}} =
             Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)

    assert honcho_files(ctx.working) == before
  end

  test "a resident with no workspace yet has nothing to export and the backup is whole", ctx do
    backed_up!(ctx)
    Clock.Fake.advance(120)
    assert {:ok, _} = Oneiroi.SimaQian.backup(ctx.r.id, ctx.actor)
    assert Map.keys(honcho_files(ctx.working)) == ["honcho/custom-instructions.md"]
    assert {:ok, nil} = Oneiroi.Proteus.memory(ctx.r.id)
  end
end
