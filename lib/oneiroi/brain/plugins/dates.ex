defmodule Oneiroi.Brain.Plugins.Dates do
  @moduledoc """
  The important dates (spec §6.7, F56). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "dates",
      name: "Important dates",
      about: "the important dates, each countdown derived on the read",
      place: :turn,
      reads: ~w(dates)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    section(
      "dates",
      Oneiroi.Sunna.dates_text(turn.resident_id),
      "the important dates with each countdown derived on this read (spec §6.7, F56): a figure never written down"
    )
  end
end
