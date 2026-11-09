defmodule Oneiroi.Brain.NeedsYou.Entry do
  @moduledoc """
  One thing waiting on the witness (brain#72, the queue abstraction):
  the contract every source's adapter returns. A struct with every key
  enforced, so an adapter that misses a field fails to compile rather
  than render wrong. `long` is the projection's, set once for all.
  """

  @enforce_keys [:kind, :ref, :since, :screen, :about]
  defstruct [:kind, :ref, :since, :screen, :about]

  @type t :: %__MODULE__{
          kind: String.t(),
          ref: integer() | String.t(),
          since: DateTime.t(),
          screen: String.t(),
          about: map()
        }
end
