defmodule Oneiroi.Kumbukumbu.Ranking do
  @moduledoc """
  The ranked index (kumbukumbu#46, design/memory-weighting.md), pure:
  given the bookmarks nearest the turn's words (C, considered), the
  learned edges out of the seed, and the exploration's draw, which are
  returned (R) and which rejected, with every score.

  A candidate scores `similarity + λ · Σ w(seed → candidate)`, the
  weights decayed to now; the seed is the top of C by similarity alone,
  what the turn is about. R is the ranked candidates above the line,
  up to the ranked share of the lines and the token budget, then the
  explored ones drawn from outside the ranked set (the 20%). With every
  weight at neutral this is plain relevance, so the first day works.
  """

  alias Oneiroi.Kumbukumbu.Edges
  alias Oneiroi.Kumbukumbu.Index

  @type candidate :: %{bookmark: map(), distance: float()}

  @doc """
  The ranking. `edges` are the learned edges out of the seeds, each with
  its source's seed count (`seeded`) and its own at the last touch;
  `opts`: `:lines` (ranked), `:explore` (lines drawn, apart, brain#68)
  and `:explore_budget` (their tokens, apart from `:budget`), `:seeds`,
  `:lambda`, `:min_score`, `:half_life` (seedings, kumbukumbu#53),
  `:citations` (the citations' summed contributions out of the seeds,
  never decayed), `:budget` (tokens), and `:draw`, the bookmarks the
  exploration may return, already shuffled at the command edge.
  """
  @spec rank([candidate()], [map()], keyword()) :: map()
  def rank(candidates, edges, opts) do
    lambda = Keyword.fetch!(opts, :lambda)
    half_life = Keyword.fetch!(opts, :half_life)
    cited = Keyword.get(opts, :citations, [])
    lines = Keyword.fetch!(opts, :lines)
    explore = Keyword.fetch!(opts, :explore)
    budget = Keyword.fetch!(opts, :budget)
    explore_budget = Keyword.get(opts, :explore_budget, budget)

    seeds =
      candidates |> Enum.take(Keyword.fetch!(opts, :seeds)) |> Enum.map(& &1.bookmark.number)

    seed_set = MapSet.new(seeds)

    # Each seed's edge to a candidate, the learned weight decayed plus the
    # citations', bounded; summed over the seeds.
    learned = Map.new(edges, &{{&1.from_number, &1.to_number}, w(&1, half_life)})
    citations = Map.new(cited, &{{&1.from_number, &1.to_number}, &1.w})

    pull =
      (Map.keys(learned) ++ Map.keys(citations))
      |> Enum.uniq()
      |> Enum.filter(fn {from, to} -> MapSet.member?(seed_set, from) and from != to end)
      |> Enum.reduce(%{}, fn {_from, to} = key, acc ->
        w = Edges.combined(Map.get(learned, key, 0.0), Map.get(citations, key, 0.0))
        Map.update(acc, to, w, &(&1 + w))
      end)

    scored =
      candidates
      |> Enum.map(fn %{bookmark: b, distance: d} ->
        similarity = 1 - d
        edge = Map.get(pull, b.number, 0.0)
        %{bookmark: b, similarity: similarity, edge: edge, score: similarity + lambda * edge}
      end)
      |> Enum.sort_by(&{-&1.score, -&1.bookmark.number})

    {above, below} = Enum.split_with(scored, &(&1.score >= Keyword.fetch!(opts, :min_score)))
    {ranked, over, _used} = take(above, lines, budget, 0)
    ranked_numbers = MapSet.new(ranked, & &1.bookmark.number)

    draw =
      opts
      |> Keyword.fetch!(:draw)
      |> Enum.reject(&MapSet.member?(ranked_numbers, &1.number))
      |> Enum.map(&%{bookmark: &1, similarity: nil, edge: nil, score: nil})

    {explored, _over, _used} = take(draw, explore, explore_budget, 0)
    explored_numbers = MapSet.new(explored, & &1.bookmark.number)

    # A near-miss the draw then returned is explored, not rejected: whether
    # it deserves better is exactly the exploration's question.
    rejected =
      (Enum.map(below, &Map.put(&1, :why, "below the line")) ++
         Enum.map(over, &Map.put(&1, :why, "past the index's ranked lines")))
      |> Enum.reject(&MapSet.member?(explored_numbers, &1.bookmark.number))

    %{seeds: seeds, ranked: ranked, explored: explored, rejected: rejected}
  end

  defp w(edge, half_life),
    do:
      Edges.decayed(
        edge.w,
        Map.get(edge, :touched_count, 0),
        Map.get(edge, :seeded, 0),
        half_life
      )

  # In order until the count or the budget is spent; what did not fit
  # is returned as `over`.
  defp take(scored, count, budget, used) do
    Enum.reduce(scored, {[], [], used}, fn s, {kept, over, used} ->
      cost = Index.tokens(Index.line(s.bookmark))

      if length(kept) < count and used + cost <= budget,
        do: {kept ++ [s], over, used + cost},
        else: {kept, over ++ [s], used}
    end)
  end
end
