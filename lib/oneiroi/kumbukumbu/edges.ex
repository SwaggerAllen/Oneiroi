defmodule Oneiroi.Kumbukumbu.Edges do
  @moduledoc """
  Learned retrieval edges (kumbukumbu#46, design/memory-weighting.md),
  the arithmetic alone, pure: what a turn's considered, returned and used
  memories teach, and how a weight decays toward neutral.

  An edge `from → to` reads "when `from` is in play, `to` is worth
  bringing". Its weight is a deviation from neutral (0), soft-bounded in
  [-1, 1] so no clique or hub runs away, and decayed lazily by tests,
  not days (kumbukumbu#53, Lily's position #65): an edge stores its
  weight and its source's seed count when last touched, and its weight
  now is `w · 2^(-(seeded - touched_count) / K)`. It ages only on turns
  where its source was the seed, where it could have fired; an edge
  whose source is never seeded freezes. Nothing sweeps every edge.

  Citations add apart from all this (kumbukumbu#53, position #64): a
  bookmark citing another gives `B` both ways; a document citing `N`
  bookmarks gives `B/(N-1)` to each ordered pair, so a survey is not N
  strong statements. A citation's contribution never decays and is
  removed exactly when the citation goes; the edge read at ranking is
  the learned weight, decayed, plus the citations', bounded in [-1, 1].

  The rules, from the resident's review (Position #45) as amended:

  1. a seed and a memory both returned: `seed → returned`, `+α`;
  3. two memories both used: each to the other, `+β`;
  4. a memory returned and not used, while another was: `used → it`,
     `-α`, never against a correction (its value is an error that did
     not happen, which leaves no trace).

  No rule learns from the ranker's own cut: a negative is written only
  from what the resident did.
  """

  @type change :: {pos_integer(), pos_integer(), float()}

  @doc "The weight `w` last touched at seed count `touched`, decayed to seed count `now` with half-life `k` seedings."
  @spec decayed(float(), non_neg_integer(), non_neg_integer(), number()) :: float()
  def decayed(w, touched, now, k), do: w * :math.pow(2, -max(now - touched, 0) / k)

  @doc "The learned weight and the citations' together, bounded in [-1, 1]."
  @spec combined(float(), float()) :: float()
  def combined(learned, cited), do: (learned + cited) |> max(-1.0) |> min(1.0)

  @doc "A document's co-citation: each ordered pair of the `numbers` it cites, `b/(n-1)` each."
  @spec co_cited([pos_integer()], float()) :: [change()]
  def co_cited(numbers, b) do
    numbers = Enum.uniq(numbers)

    case length(numbers) do
      n when n < 2 -> []
      n -> for x <- numbers, y <- numbers, x != y, do: {x, y, b / (n - 1)}
    end
  end

  @doc "A bookmark citing others: `b` each way."
  @spec cited_by_bookmark(pos_integer(), [pos_integer()], float()) :: [change()]
  def cited_by_bookmark(number, cited, b),
    do:
      for(c <- Enum.uniq(cited), c != number, edge <- [{number, c, b}, {c, number, b}], do: edge)

  @doc "`w` moved by `delta`, softly bounded in [-1, 1]: diminishing returns at either end."
  @spec bump(float(), float()) :: float()
  def bump(w, delta) when delta >= 0, do: w + delta * (1 - w)
  def bump(w, delta), do: w + delta * (1 + w)

  @doc "Rule 1: every seed toward every other memory returned with it."
  @spec co_returned([pos_integer()], [pos_integer()], float()) :: [change()]
  def co_returned(seeds, returned, alpha),
    do: for(s <- Enum.uniq(seeds), r <- Enum.uniq(returned), s != r, do: {s, r, alpha})

  @doc """
  Rules 3 and 4, once a turn's use is known: the used memories toward
  each other, `+β`; each used memory toward each returned and unused
  one, `-α`, but never toward one in `exempt` (the corrections).
  """
  @spec used([pos_integer()], [pos_integer()], MapSet.t(), float(), float()) :: [change()]
  def used(used, returned, exempt, alpha, beta) do
    used = Enum.uniq(used)
    together = for u <- used, v <- used, u != v, do: {u, v, beta}

    ignored =
      for u <- used,
          a <- Enum.uniq(returned),
          a not in used,
          not MapSet.member?(exempt, a),
          do: {u, a, -alpha}

    together ++ ignored
  end
end
