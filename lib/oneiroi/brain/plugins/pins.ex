defmodule Oneiroi.Brain.Plugins.Pins do
  @moduledoc """
  The pins (kumbukumbu#45, brain#48), in the stable prefix. A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Kumbukumbu

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "pins",
      name: "Pins",
      about: "the moments you pinned, kept in front of you always and never ranked",
      place: :prefix,
      reads: ~w(bookmarks)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx), do: pins_section(turn)

  # The pins (kumbukumbu#45, brain#48): decisions, so in the stable
  # prefix with the identity files and cached with them, and never in the
  # ranked index. They change rarely; an adapter's session sees a new one
  # at its next prefix.
  defp pins_section(turn) do
    case Kumbukumbu.pins(turn.resident_id, Map.get(turn, :session_key)) do
      [] ->
        []

      pins ->
        text =
          "# Pinned\n\nThe moments you pinned: decisions, kept in front of you always and never ranked. bookmark_open(number) reads any.\n\n" <>
            Enum.map_join(pins, "\n", &Kumbukumbu.Index.line(&1, Local.zone(turn.resident_id)))

        section(
          "pins",
          text,
          "the pins (kumbukumbu#45): #{length(pins)} decisions in the stable prefix, never ranked",
          %{refs: Enum.map(pins, & &1.number)}
        )
    end
  end
end
