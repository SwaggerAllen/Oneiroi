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
  The ranking. `opts`: `:lines`, `:explore` (lines drawn, of `:lines`),
  `:seeds`, `:lambda`, `:min_score`, `:half_life` (days), `:budget`
  (tokens), `:now`, and `:draw`, the bookmarks the exploration may
  return, already shuffled at the command edge.
  """
  @spec rank([candidate()], [map()], keyword()) :: map()
  def rank(candidates, edges, opts) do
    now = Keyword.fetch!(opts, :now)
    lambda = Keyword.fetch!(opts, :lambda)
    half_life = Keyword.fetch!(opts, :half_life)
    lines = Keyword.fetch!(opts, :lines)
    explore = min(Keyword.fetch!(opts, :explore), lines)
    budget = Keyword.fetch!(opts, :budget)

    seeds =
      candidates |> Enum.take(Keyword.fetch!(opts, :seeds)) |> Enum.map(& &1.bookmark.number)

    seed_set = MapSet.new(seeds)

    pull =
      Enum.reduce(edges, %{}, fn e, acc ->
        if MapSet.member?(seed_set, e.from_number) and e.from_number != e.to_number,
          do: Map.update(acc, e.to_number, w(e, now, half_life), &(&1 + w(e, now, half_life))),
          else: acc
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
    {ranked, over, used} = take(above, lines - explore, budget, 0)
    ranked_numbers = MapSet.new(ranked, & &1.bookmark.number)

    draw =
      opts
      |> Keyword.fetch!(:draw)
      |> Enum.reject(&MapSet.member?(ranked_numbers, &1.number))
      |> Enum.map(&%{bookmark: &1, similarity: nil, edge: nil, score: nil})

    {explored, _over, _used} = take(draw, explore, budget, used)
    explored_numbers = MapSet.new(explored, & &1.bookmark.number)

    # A near-miss the draw then returned is explored, not rejected: whether
    # it deserves better is exactly the exploration's question.
    rejected =
      (Enum.map(below, &Map.put(&1, :why, "below the line")) ++
         Enum.map(over, &Map.put(&1, :why, "past the index's ranked lines")))
      |> Enum.reject(&MapSet.member?(explored_numbers, &1.bookmark.number))

    %{seeds: seeds, ranked: ranked, explored: explored, rejected: rejected}
  end

  defp w(edge, now, half_life), do: Edges.decayed(edge.w, edge.touched_at, now, half_life)

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
