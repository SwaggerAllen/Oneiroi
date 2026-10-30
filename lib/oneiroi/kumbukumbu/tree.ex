defmodule Oneiroi.Kumbukumbu.Tree do
  @moduledoc """
  The tree port (spec §6.17, P39: tags are citations): who answers which
  tree nodes (a soul line, a habit, a seed) cite a moment, so a bookmark
  is shown with the tree's tags beside its closed-set ones and the
  resident's own tree is the vocabulary.

  A port rather than a call because the character layer reads this
  system's moments (ethos #3) and a direct call back is the cycle
  Boundary and `mix xref graph --format cycles` both reject (sunna #12's
  shape). The implementation is named in `KUMBUKUMBU_TREE` and read at
  the call, so neither compiler sees an edge; the tags it returns are
  `kind/number`, never a slug of the closed set.
  """

  @doc "The tree's tags on the targets named, each id to its sorted `kind/number` tags; an uncited id is absent."
  @callback tags_of(
              resident_id :: String.t(),
              target_kind :: String.t(),
              target_ids :: [String.t()]
            ) :: %{String.t() => [String.t()]}
end
