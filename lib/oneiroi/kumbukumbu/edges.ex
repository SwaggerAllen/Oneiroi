defmodule Oneiroi.Kumbukumbu.Edges do
  @moduledoc """
  Learned retrieval edges (kumbukumbu#46, design/memory-weighting.md),
  the arithmetic alone, pure: what a turn's considered, returned and used
  memories teach, and how a weight decays toward neutral.

  An edge `from → to` reads "when `from` is in play, `to` is worth
  bringing". Its weight is a deviation from neutral (0), soft-bounded in
  [-1, 1] so no clique or hub runs away, and decayed lazily: an edge
  stores its weight and when it was last touched, and its weight at `t`
  is `w · 2^(-(t - touched_at) / half_life)`. Nothing sweeps every edge.

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

  @doc "The weight `w` last touched at `touched_at`, decayed to `at`."
  @spec decayed(float(), DateTime.t(), DateTime.t(), number()) :: float()
  def decayed(w, %DateTime{} = touched_at, %DateTime{} = at, half_life_days) do
    days = max(DateTime.diff(at, touched_at, :second), 0) / 86_400
    w * :math.pow(2, -days / half_life_days)
  end

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
