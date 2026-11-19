defmodule Oneiroi.Brain.Plugins.Honcho do
  @moduledoc """
  Honcho's context (spec §5), retired (proteus#20; the witness,
  2026-11-18: "cut honcho altogether"). Nothing is synced to Honcho and
  nothing is read from it, so its section is always empty and never
  sent. The slot stays in the list, saying so, until the resident's
  proposal to switch it off is answered (brain#68); then it goes.
  """
  @behaviour Oneiroi.Brain.Plugin

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "honcho",
      name: "Honcho (retired)",
      about:
        "retired on 2026-11-18: the background model's context is no longer read, and this section is always empty",
      place: :turn,
      reads: ~w(background_model)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(_turn, _ctx), do: []
end
