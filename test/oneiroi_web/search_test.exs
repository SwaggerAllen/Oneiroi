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

  defp capture_at!(ctx, ref, content, at) do
    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        ref,
        at,
        [%{role: :assistant, content: content, sent_at: at, actor: ctx.brain}],
        ctx.brain
      )
  end

  test "the words scope pages, sorts oldest or newest and keeps to a date range (kumbukumbu#67)",
       ctx do
    day = 86_400
    capture_at!(ctx, "t1", "The wren sang, first.", ctx.at)
    capture_at!(ctx, "t2", "The wren sang, second.", DateTime.add(ctx.at, 2 * day))
    capture_at!(ctx, "t3", "The wren sang, third.", DateTime.add(ctx.at, 4 * day))

    get = fn params ->
      ctx.conn
      |> get("/v1/residents/#{ctx.id}/search", Map.merge(%{q: "wren", scope: "words"}, params))
    end

    turns = fn body -> Enum.map(body["results"], & &1["ref"]["turn_ref"]) end

    body = get.(%{}) |> json_response(200)
    assert turns.(body) == ["t3", "t2", "t1"]
    assert %{"page" => 1, "more" => false} = body

    assert get.(%{sort: "oldest"}) |> json_response(200) |> turns.() == ["t1", "t2", "t3"]

    from = DateTime.add(ctx.at, day) |> DateTime.to_iso8601()
    to = DateTime.add(ctx.at, 3 * day) |> DateTime.to_iso8601()
    assert get.(%{from: from, to: to}) |> json_response(200) |> turns.() == ["t2"]
    assert get.(%{from: from}) |> json_response(200) |> turns.() == ["t3", "t2"]

    assert %{"results" => [], "page" => 2, "more" => false} =
             get.(%{page: "2"}) |> json_response(200)

    for bad <- [%{page: "0"}, %{page: "x"}, %{sort: "best"}, %{from: "yesterday"}] do
      assert %{"error" => %{"kind" => "search_paging_invalid"}} = get.(bad) |> json_response(422)
    end

    # A page is `limit` long, and `more` says another follows.
    page = fn n ->
      Kumbukumbu.search_words_page({:resident, ctx.id}, ctx.id, "wren",
        limit: 2,
        offset: (n - 1) * 2
      )
    end

    assert {[_, _], true} = page.(1)
    assert {[{%{turn_ref: "t1"}, _session}], false} = page.(2)
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

  defp searched(ctx, params) do
    ctx.conn |> get("/v1/residents/#{ctx.id}/search", params)
  end

  defp refs(body, key), do: Enum.map(body["results"], & &1["ref"][key])

  test "transcripts narrow by who said it and the kind of conversation (kumbukumbu#69)", ctx do
    capture!(ctx, ctx.key, "t-her", "The plover ran along the sand.")

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        "t-his",
        ctx.at,
        [%{role: :user, content: "Did you see the plover?", sent_at: ctx.at, actor: ctx.actor}],
        ctx.brain
      )

    turns = fn params ->
      searched(ctx, Map.merge(%{q: "plover", scope: "words"}, params))
      |> json_response(200)
      |> refs("turn_ref")
    end

    assert Enum.sort(turns.(%{})) == ["t-her", "t-his"]
    assert turns.(%{who: "resident"}) == ["t-her"]
    assert turns.(%{who: "witness"}) == ["t-his"]
    assert Enum.sort(turns.(%{conversations: "main"})) == ["t-her", "t-his"]
    assert turns.(%{conversations: "work,round"}) == []

    for bad <- [%{who: "everyone"}, %{conversations: "main,parlour"}] do
      assert %{"error" => %{"kind" => "search_paging_invalid"}} =
               searched(ctx, Map.merge(%{q: "plover", scope: "words"}, bad)) |> json_response(422)
    end
  end

  test "bookmarks narrow to pinned, a tag, who made them, and their moment; and sort (kumbukumbu#69)",
       ctx do
    capture!(ctx, ctx.key, "t1", "a moment")
    plain = bookmark!(ctx, ctx.key, "t1", "the kestrel, first", nil)
    tagged = bookmark!(ctx, ctx.key, "t1", "the kestrel, tagged", nil)
    :ok = Kumbukumbu.create_tag(ctx.id, "birds", ctx.actor)
    :ok = Kumbukumbu.apply_tag(ctx.id, "birds", "bookmark", tagged, ctx.actor)
    :ok = Kumbukumbu.pin_bookmark(ctx.id, plain, ctx.brain)

    numbers = fn params ->
      searched(ctx, Map.merge(%{q: "kestrel", scope: "bookmarks"}, params))
      |> json_response(200)
      |> refs("number")
    end

    assert Enum.sort(numbers.(%{})) == Enum.sort([plain, tagged])
    assert numbers.(%{pinned: "true"}) == [plain]
    assert numbers.(%{tag: "birds"}) == [tagged]
    assert Enum.sort(numbers.(%{made_by: "resident"})) == Enum.sort([plain, tagged])
    assert numbers.(%{made_by: "witness"}) == []
    later = DateTime.add(ctx.at, 3600) |> DateTime.to_iso8601()
    assert numbers.(%{from: later}) == []
    assert length(numbers.(%{sort: "oldest"})) == 2

    for bad <- [%{made_by: "someone"}, %{sort: "best"}, %{from: "soon"}] do
      assert %{"error" => %{"kind" => "search_filter_invalid"}} =
               searched(ctx, Map.merge(%{q: "kestrel", scope: "bookmarks"}, bad))
               |> json_response(422)
    end
  end

  test "records narrow by kind, author, folder and a created or updated range (kumbukumbu#69)",
       ctx do
    {:ok, _} =
      Seshat.write(ctx.id, "writing/heron.md", "# Heron\n\nThe heron on the weir.", ctx.brain)

    {:ok, _} =
      Seshat.write(
        ctx.id,
        "design/weir-notes.md",
        "# Weir\n\nA heron at the weir again.",
        ctx.brain
      )

    paths = fn params ->
      searched(ctx, Map.merge(%{q: "heron", scope: "records"}, params))
      |> json_response(200)
      |> refs("path")
      |> Enum.sort()
    end

    assert paths.(%{}) == ["design/weir-notes.md", "writing/heron.md"]
    assert paths.(%{kinds: "writing"}) == ["writing/heron.md"]
    assert paths.(%{kinds: "writing,design"}) == ["design/weir-notes.md", "writing/heron.md"]
    assert paths.(%{folder: "design/"}) == ["design/weir-notes.md"]
    assert paths.(%{author: "resident"}) == ["design/weir-notes.md", "writing/heron.md"]
    assert paths.(%{author: "witness"}) == []
    future = DateTime.add(Clock.now(), 86_400) |> DateTime.to_iso8601()
    assert paths.(%{from: future}) == []
    assert paths.(%{from: future, date: "created"}) == []
    assert paths.(%{to: future, date: "created"}) == ["design/weir-notes.md", "writing/heron.md"]

    assert %{"error" => %{"kind" => "search_filter_invalid"}} =
             searched(ctx, %{q: "heron", scope: "records", date: "someday"}) |> json_response(422)
  end

  test "scenes narrow by mood and person, by their day (kumbukumbu#69)", ctx do
    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => "2026-11-08",
          "title" => "The heron at dusk",
          "from_turn" => "t1",
          "to_turn" => "t1",
          "summary" => "We watched the heron until dark.",
          "mood" => "quiet, glad",
          "people" => ["Andrew"],
          "register" => "his"
        },
        ctx.brain
      )

    days = fn params ->
      searched(ctx, Map.merge(%{q: "heron", scope: "scenes"}, params))
      |> json_response(200)
      |> refs("day")
    end

    assert days.(%{}) == ["2026-11-08"]
    assert days.(%{mood: "glad"}) == ["2026-11-08"]
    assert days.(%{mood: "furious"}) == []
    assert days.(%{person: "andrew"}) == ["2026-11-08"]
    assert days.(%{person: "Iris"}) == []
    assert days.(%{from: "2026-11-09T00:00:00Z"}) == []
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
