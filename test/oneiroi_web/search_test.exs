defmodule OneiroiWeb.SearchTest do
  @moduledoc """
  The one search (kumbukumbu#59, seshat#53, spec F66): each scope, the
  interleaving, the bookmarks by line, summary and tags, what her memory
  would surface, the typed result's shape, the bounds, and never the
  words of a private, unshared session.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Seshat

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    id = resident.id
    actor = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(account.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(id, account.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(id)
    Model.clear()

    on_exit(fn ->
      Model.clear(for: id)
      File.rm_rf!(dir)
    end)

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

  defp bookmark!(ctx, key, ref, line, summary \\ nil) do
    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{session_key: key, anchor_ref: ref, line: line, summary: summary},
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

  defp search(ctx, q, scope \\ nil) do
    params = if scope, do: %{q: q, scope: scope}, else: %{q: q}
    ctx.conn |> get("/v1/residents/#{ctx.id}/search", params) |> json_response(200)
  end

  # A scene row (seshat#52); its day's file, scenes/<day>.md, is rendered
  # from the rows and indexed like any document.
  defp scene!(ctx, day, title, summary) do
    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => day,
          "title" => title,
          "from_turn" => "t1",
          "to_turn" => "t1",
          "summary" => summary,
          "register" => "his"
        },
        ctx.brain
      )

    :ok
  end

  test "a private, unshared session's words are never returned, by the words scope, everything, or the transcripts search before it; shared, they are",
       ctx do
    capture!(ctx, ctx.key, "t-main", "The kestrel was over the field.")
    free = private_session!(ctx)
    capture!(ctx, free, "t-free", "A secret kestrel, mine alone.")
    bookmark!(ctx, free, "t-free", "the kestrel alone", "a free-time kestrel")

    assert %{"results" => [only]} = search(ctx, "kestrel", "words")
    assert %{"type" => "transcript", "ref" => %{"session_key" => key}} = only
    assert key == ctx.key
    refute inspect(search(ctx, "kestrel")) =~ "secret"
    refute inspect(search(ctx, "kestrel")) =~ "alone"
    assert %{"results" => []} = search(ctx, "secret", "words")
    assert %{"results" => []} = search(ctx, "kestrel", "bookmarks")

    # The transcripts search before this one leaves them out too: the
    # policy keys the messages to the resident (kumbukumbu#28).
    refute ctx.conn
           |> get("/v1/residents/#{ctx.id}/transcripts/search", %{q: "secret"})
           |> json_response(200)
           |> Enum.any?()

    :ok = Kumbukumbu.share_session(ctx.id, free, "you may read this one", ctx.brain)

    assert %{"results" => [%{"snippet" => "A secret kestrel, mine alone."}]} =
             search(ctx, "secret", "words")

    assert %{"results" => [%{"type" => "bookmark"}]} = search(ctx, "kestrel", "bookmarks")
  end

  test "the words scope: the transcripts' messages, newest first, each with its session, turn and cursor",
       ctx do
    capture!(ctx, ctx.key, "t1", "The heron stood still.")
    capture!(ctx, ctx.key, "t2", "Then the heron flew.")

    assert %{"q" => "heron", "scope" => "words", "results" => [newer, older]} =
             search(ctx, "heron", "words")

    assert %{
             "type" => "transcript",
             "ref" => %{"session_key" => key, "turn_ref" => "t2", "cursor" => cursor},
             "title" => "Oneiroi chat",
             "snippet" => "Then the heron flew.",
             "at" => at,
             "score" => nil
           } = newer

    assert key == ctx.key and cursor =~ ~r/^\d+:0$/
    assert {:ok, _, _} = DateTime.from_iso8601(at)
    assert %{"ref" => %{"turn_ref" => "t1"}} = older
  end

  test "the bookmarks scope searches the line, the summary and the tags, the line's matches first",
       ctx do
    capture!(ctx, ctx.key, "t1", "a moment")
    tagged = bookmark!(ctx, ctx.key, "t1", "tea at four", "the kettle")
    summary = bookmark!(ctx, ctx.key, "t1", "the walk home", "we saw an otter by the weir")
    line = bookmark!(ctx, ctx.key, "t1", "the otter", nil)
    _other = bookmark!(ctx, ctx.key, "t1", "granite", "a sonnet")
    :ok = Kumbukumbu.create_tag(ctx.id, "otter", ctx.actor)
    :ok = Kumbukumbu.apply_tag(ctx.id, "otter", "bookmark", tagged, ctx.actor)

    assert %{"results" => results} = search(ctx, "OTTER", "bookmarks")
    assert Enum.map(results, & &1["ref"]["number"]) == [line, summary, tagged]
    assert Enum.map(results, & &1["score"]) == [1.0, 0.67, 0.33]

    assert %{
             "type" => "bookmark",
             "title" => "the walk home",
             "snippet" => "we saw an otter by the weir",
             "at" => at
           } = Enum.at(results, 1)

    assert is_binary(at)
  end

  test "records are the library's documents but the scenes; scenes are scenes/<day>.md by the prefix",
       ctx do
    {:ok, _} =
      Seshat.write(ctx.id, "writing/heron.md", "# Heron\n\nThe heron on the weir.", ctx.brain)

    scene!(ctx, "2026-11-08", "The heron at dusk", "We watched the heron until dark.")

    assert %{"results" => records} = search(ctx, "heron", "records")
    assert [%{"type" => "document", "ref" => %{"path" => "writing/heron.md"}} = doc] = records
    assert %{"title" => "Heron", "snippet" => snippet, "score" => score} = doc
    assert snippet =~ "heron on the weir" and is_float(score) and is_binary(doc["at"])

    assert %{"results" => [scene]} = search(ctx, "heron", "scenes")

    assert %{
             "type" => "scene",
             "ref" => %{"day" => "2026-11-08", "id" => nil, "path" => "scenes/2026-11-08.md"},
             "at" => nil,
             "score" => s
           } = scene

    assert is_float(s) and scene["title"] in ["The heron at dusk", "Scenes of 2026-11-08"]
  end

  test "everything interleaves the scopes, one of each a round, records, bookmarks, scenes, words",
       ctx do
    {:ok, _} = Seshat.write(ctx.id, "writing/wren.md", "# Wren\n\nA wren sang.", ctx.brain)
    scene!(ctx, "2026-11-09", "The wren", "The wren again.")

    capture!(ctx, ctx.key, "t1", "Did you hear the wren?")
    bookmark!(ctx, ctx.key, "t1", "the wren")
    bookmark!(ctx, ctx.key, "t1", "a second wren")

    assert %{"scope" => "everything", "results" => results} = search(ctx, "wren")

    assert Enum.map(results, & &1["type"]) ==
             ~w(document bookmark scene transcript bookmark)

    # Every result has the one shape, whatever its type.
    for r <- results,
        do: assert(Enum.sort(Map.keys(r)) == ~w(at ref score snippet title type))
  end

  test "as she sees it is what her memory would surface for the words: the ranked index then the madeleine, never a pin, never a private session's",
       ctx do
    capture!(ctx, ctx.key, "t1", "a moment")
    garden = bookmark!(ctx, ctx.key, "t1", "the garden shed", "she asked about the garden")
    _tea = bookmark!(ctx, ctx.key, "t1", "tea at four", "the kettle")
    pinned = bookmark!(ctx, ctx.key, "t1", "the garden gate", "the gate stuck")
    :ok = Kumbukumbu.pin_bookmark(ctx.id, pinned, ctx.actor)
    free = private_session!(ctx)
    capture!(ctx, free, "t-free", "alone")
    _private = bookmark!(ctx, free, "t-free", "the garden at night", "garden alone")

    assert %{"scope" => "as-she-sees-it", "results" => results} =
             search(ctx, "garden", "as-she-sees-it")

    numbers = Enum.map(results, & &1["ref"]["number"])
    assert [%{"type" => "bookmark", "score" => score} | _] = results
    assert hd(numbers) == garden and is_float(score)
    refute pinned in numbers
    refute inspect(results) =~ "at night"

    # The text search finds the pin; her memory does not hand it to her.
    assert pinned in Enum.map(
             search(ctx, "garden", "bookmarks")["results"],
             & &1["ref"]["number"]
           )
  end

  test "the bounds: a query under two characters and a scope not listed are refused as declared",
       ctx do
    for params <- [%{q: "a"}, %{q: " a  "}, %{}] do
      assert %{"error" => %{"kind" => "query_too_short", "site" => "web_search_query_too_short"}} =
               ctx.conn |> get("/v1/residents/#{ctx.id}/search", params) |> json_response(422)
    end

    assert %{"error" => %{"kind" => "scope_unknown"}} =
             ctx.conn
             |> get("/v1/residents/#{ctx.id}/search", %{q: "heron", scope: "dreams"})
             |> json_response(422)

    assert %{"results" => []} = search(ctx, "ok")
  end

  test "with the witness's reads switched off, bookmarks are refused and left out of everything",
       ctx do
    capture!(ctx, ctx.key, "t1", "the lark")
    bookmark!(ctx, ctx.key, "t1", "the lark")

    {:ok, 1} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{"witness_reads" => false},
        "My journal and bookmarks are mine.",
        "hers",
        ctx.actor
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, 1, "agreed", ctx.brain)

    for scope <- ["bookmarks", "as-she-sees-it"] do
      assert %{"error" => %{"kind" => "switched_off"}} =
               ctx.conn
               |> get("/v1/residents/#{ctx.id}/search", %{q: "lark", scope: scope})
               |> json_response(403)
    end

    assert %{"results" => [%{"type" => "transcript"}]} = search(ctx, "lark")
  end

  test "another account's resident is not found" do
    other = Fixtures.account!()
    resident = Fixtures.resident!(Fixtures.account!())

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: other.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    assert %{"error" => %{"kind" => "agathos_daimon_not_witnessed"}} =
             conn
             |> get("/v1/residents/#{resident.id}/search", %{q: "heron"})
             |> json_response(404)
  end
end
