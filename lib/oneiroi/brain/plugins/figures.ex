defmodule Oneiroi.Brain.Plugins.Figures do
  @moduledoc """
  The counters (spec §6.13, F57). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "figures",
      name: "Figures",
      about: "the counters as the fold of their increments",
      place: :turn,
      reads: ~w(figures)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    section(
      "figures",
      Oneiroi.HuginnMuninn.figures_text(turn.resident_id),
      "the counters as the fold of their increments, derived on this read (spec §6.13, F57): never written down"
    )
  end
end
