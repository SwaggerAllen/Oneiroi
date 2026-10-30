defmodule Oneiroi.Register do
  @moduledoc """
  The register a resident-authored record is written in (spec §6.13, P8:
  the corpus-shape report): correction, praise, instruction or play,
  tagged by the resident at write time and never judged after, with no
  model call. One closed list in the kernel because memory's bookmarks
  and the library's journal both carry it and the audits count across
  both; a record may carry none, which the report counts as untagged.
  """

  @registers ~w(correction praise instruction play)

  @doc "The registers, in the order the report shows them."
  @spec all() :: [String.t()]
  def all, do: @registers

  @doc "Whether a value is a register or absent."
  @spec ok?(term()) :: boolean()
  def ok?(nil), do: true
  def ok?(value), do: value in @registers
end
