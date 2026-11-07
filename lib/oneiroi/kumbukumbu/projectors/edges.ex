defmodule Oneiroi.Kumbukumbu.Projectors.Edges do
  @moduledoc """
  Folds what retrieval did into learned edges (kumbukumbu#46): rule 1
  as a turn's index is recorded (its seed and what it returned), rules 3
  and 4 once the turn's `memory_feedback` says what helped. A turn with
  no feedback learns rule 1 alone, so a forgotten call never demotes
  anything. Decay is computed from the events' own instants, so a
  rebuild reproduces every weight. The arithmetic is
  `Oneiroi.Kumbukumbu.Edges`'.
  """
  # Renamed with kumbukumbu#53, so the edges are folded again from the
  # first event under decay by tests and the citations; the migration
  # empties the tables the old name folded.
  use Oneiroi.Projection, name: "kumbukumbu_edges_2"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Edges
  alias Oneiroi.Kumbukumbu.Events
  alias Oneiroi.Kumbukumbu.Events.Memory, as: MemoryEvents
  alias Oneiroi.Kumbukumbu.Store.{Bookmark, CitationEdge, Edge, EdgeSource, EdgeTurn}

  fold(%Events.RetrievalRecorded{} = e, _metadata, fn multi ->
    Multi.run(multi, :edges, fn repo, _changes -> {:ok, learn(repo, e)} end)
  end)

  # A document's citations (kumbukumbu#53): what it contributed before is
  # removed whole and what it cites now is added, so an edit that drops
  # a citation unwinds exactly its part and nothing learned is touched.
  fold(%MemoryEvents.CitationsRecorded{} = e, _metadata, fn multi ->
    Multi.run(multi, :citations, fn repo, _changes ->
      {:ok, cite(repo, e.id, e.source, Edges.co_cited(e.numbers, citation_b()))}
    end)
  end)

  # A bookmark citing others in its own words: `B` each way.
  fold(%MemoryEvents.BookmarkAdded{} = e, _metadata, fn multi ->
    cited = cited_bookmarks("#{e.line} #{e.summary}")

    Multi.run(multi, :citations, fn repo, _changes ->
      {:ok,
       cite(
         repo,
         e.id,
         "bookmark/#{e.number}",
         Edges.cited_by_bookmark(e.number, cited, citation_b())
       )}
    end)
  end)

  defp cite(repo, resident_id, source, changes) do
    repo.delete_all(
      from(c in CitationEdge, where: c.resident_id == ^resident_id and c.source == ^source)
    )

    rows =
      for {from, to, w} <- changes,
          do: %{resident_id: resident_id, source: source, from_number: from, to_number: to, w: w}

    if rows != [], do: repo.insert_all(CitationEdge, rows)
    :ok
  end

  # `<slug>:bookmark/<n>` in a bookmark's own words. The slug is not
  # checked here (the projector does not know it), so another resident's
  # citation would count: there is no sharing between residents yet.
  defp cited_bookmarks(text) do
    ~r/(?<![\w\/:])[a-z][a-z0-9-]*:bookmark\/(\d+)/
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(fn [n] -> String.to_integer(n) end)
  end

  defp citation_b, do: Config.fetch!(:kumbukumbu, :edge_citation_permille) / 1000

  defp learn(repo, e) do
    uses = Enum.map(e.uses, &normal/1)
    seeds = numbers(uses, &(&1.stage == "seed"))
    returned = numbers(uses, &(&1.stage == "returned"))
    # Rule 1 reads the ranked returns alone: an explored one was drawn at
    # random, so its co-return with the seed says nothing about it. It
    # learns from use, as everything returned does.
    ranked = numbers(uses, &(&1.stage == "returned" and &1.via == "index"))
    used = numbers(uses, &(&1.stage == "used"))
    feedback? = Enum.any?(uses, &(&1.via == "feedback"))
    indexed? = seeds != [] or Enum.any?(uses, &(&1.via in ["index", "explored"]))
    alpha = Config.fetch!(:kumbukumbu, :edge_alpha_permille) / 1000
    beta = Config.fetch!(:kumbukumbu, :edge_beta_permille) / 1000

    {turn, first_index?} = remember(repo, e, returned, used, indexed?, feedback?)
    # A turn's seeds are its sources' tests (kumbukumbu#53): counted once
    # a turn, when its index first arrives, before what it teaches.
    if first_index?, do: seed(repo, e.resident_id, seeds)
    apply_changes(repo, e, Edges.co_returned(seeds, ranked, alpha))

    if turn.indexed and turn.feedback and is_nil(turn.learned_at) do
      exempt = corrections(repo, e.resident_id, turn.returned)
      apply_changes(repo, e, Edges.used(turn.used, turn.returned, exempt, alpha, beta))

      repo.update_all(
        from(t in EdgeTurn, where: t.resident_id == ^e.resident_id and t.turn_ref == ^e.turn_ref),
        set: [learned_at: e.at]
      )
    end

    :ok
  end

  # The turn's returned and used numbers, gathered across its recordings
  # (an adapter's turn records once per tool call; a platform turn its
  # tools before its index), with whether its index and its feedback
  # have each arrived: the use rules wait for both, in either order.
  defp remember(repo, e, returned, used, indexed?, feedback?) do
    before =
      repo.one(
        from(t in EdgeTurn, where: t.resident_id == ^e.resident_id and t.turn_ref == ^e.turn_ref)
      ) ||
        %EdgeTurn{resident_id: e.resident_id, turn_ref: e.turn_ref, returned: [], used: []}

    row = %{
      before
      | returned: Enum.uniq(before.returned ++ returned),
        used: Enum.uniq(before.used ++ used),
        indexed: before.indexed || indexed?,
        feedback: before.feedback || feedback?
    }

    first_index? = indexed? and not before.indexed

    repo.insert!(row,
      on_conflict: {:replace, [:returned, :used, :indexed, :feedback]},
      conflict_target: [:resident_id, :turn_ref]
    )

    {row, first_index?}
  end

  defp seed(_repo, _resident_id, []), do: :ok

  defp seed(repo, resident_id, seeds) do
    rows = for n <- Enum.uniq(seeds), do: %{resident_id: resident_id, number: n, seeded: 1}

    repo.insert_all(EdgeSource, rows,
      on_conflict: [inc: [seeded: 1]],
      conflict_target: [:resident_id, :number]
    )

    :ok
  end

  defp corrections(_repo, _resident_id, []), do: MapSet.new()

  defp corrections(repo, resident_id, numbers) do
    from(b in Bookmark,
      where:
        b.resident_id == ^resident_id and b.number in ^numbers and b.register == "correction",
      select: b.number
    )
    |> repo.all()
    |> MapSet.new()
  end

  defp apply_changes(_repo, _e, []), do: :ok

  defp apply_changes(repo, e, changes) do
    k = Config.fetch!(:kumbukumbu, :edge_half_life_opportunities)
    floor = Config.fetch!(:kumbukumbu, :edge_floor_permille) / 1000
    froms = changes |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    existing =
      from(x in Edge, where: x.resident_id == ^e.resident_id and x.from_number in ^froms)
      |> repo.all()
      |> Map.new(&{{&1.from_number, &1.to_number}, &1})

    seeded =
      from(s in EdgeSource,
        where: s.resident_id == ^e.resident_id and s.number in ^froms,
        select: {s.number, s.seeded}
      )
      |> repo.all()
      |> Map.new()

    changes
    |> Enum.group_by(fn {from, to, _delta} -> {from, to} end, fn {_f, _t, delta} -> delta end)
    |> Enum.each(fn {{from, to}, deltas} ->
      count = Map.get(seeded, from, 0)

      start =
        case existing[{from, to}] do
          nil -> 0.0
          edge -> Edges.decayed(edge.w, edge.touched_count, count, k)
        end

      w = Enum.reduce(deltas, start, &Edges.bump(&2, &1))
      write(repo, e, {from, to, count}, w, floor)
    end)
  end

  defp write(repo, e, {from, to, _count}, w, floor) when abs(w) < floor do
    repo.delete_all(
      from(x in Edge,
        where: x.resident_id == ^e.resident_id and x.from_number == ^from and x.to_number == ^to
      )
    )
  end

  defp write(repo, e, {from, to, count}, w, _floor) do
    repo.insert!(
      %Edge{
        resident_id: e.resident_id,
        from_number: from,
        to_number: to,
        w: w,
        touched_at: e.at,
        touched_count: count
      },
      on_conflict: {:replace, [:w, :touched_at, :touched_count]},
      conflict_target: [:resident_id, :from_number, :to_number]
    )
  end

  defp numbers(uses, keep) do
    for %{target: "bookmark/" <> n} = use <- uses,
        keep.(use),
        {number, ""} <- [Integer.parse(n)],
        do: number
  end

  defp normal(use) do
    %{
      target: Map.get(use, :target) || Map.get(use, "target"),
      stage: Map.get(use, :stage) || Map.get(use, "stage"),
      via: Map.get(use, :via) || Map.get(use, "via")
    }
  end
end
