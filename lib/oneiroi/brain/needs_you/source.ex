defmodule Oneiroi.Brain.NeedsYou.Source do
  @moduledoc """
  A source of what waits on the witness (brain#72): a system whose rows
  move through a flow with stages, each held by someone. A source
  declares the stages the witness holds (each an entry kind and the
  screen its decision is made on) and returns the entries in them. The
  projection shows exactly the declared stages; an entry of a kind its
  source did not declare is refused, loudly.
  """

  alias Oneiroi.Brain.NeedsYou.Entry

  @doc "The witness-held stages this source projects: each an entry kind and its screen."
  @callback stages() :: [%{kind: String.t(), screen: String.t()}]

  @doc "The resident's entries in those stages."
  @callback entries(resident_id :: String.t()) :: [Entry.t()]
end
