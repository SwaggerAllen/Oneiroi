defmodule Oneiroi.Brain.Plugins.Madeleine do
  @moduledoc """
  The madeleine (spec §6.3, P10). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Kumbukumbu

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "madeleine",
      name: "A madeleine",
      about: "one adjacent, unheard bookmark, by nearness and never by rank",
      place: :turn,
      reads: ~w(bookmarks)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, ctx),
    do: madeleine_section(turn, madeleine(turn, ctx.vector, ctx.index.included))

  # The madeleine is chosen by nearness to the words the turn opens with,
  # and the choice is an embedding billed to the dyad; a preview records
  # nothing and bills nothing, so it shows the section's place and why it
  # was not run, and sends nothing for it (brain#41).
  defp madeleine_section(%{preview?: true}, _recall) do
    [
      %{
        label: "madeleine",
        message: nil,
        injection: %{
          tokens: 0,
          reason:
            "the madeleine (spec §6.3, P10): chosen by nearness to what is said next, which costs an embedding, so a preview does not run it",
          run: false
        }
      }
    ]
  end

  defp madeleine_section(turn, recall) do
    section(
      "madeleine",
      madeleine_text(recall, Local.zone(turn.resident_id)),
      recall &&
        "the madeleine (spec §6.3, P10), by nearness and never by rank: #{recall.reason}",
      # The text rides the row, as the index's does, so the recall is
      # read later as what was shown and not only why.
      %{
        text: madeleine_text(recall, Local.zone(turn.resident_id)),
        refs: (recall && [recall.bookmark.number]) || []
      }
    )
  end

  defp madeleine(%{preview?: true}, _vector, _indexed), do: nil

  defp madeleine(turn, vector, indexed),
    do: Kumbukumbu.madeleine_near(turn.resident_id, vector, turn.session_key, indexed)

  defp madeleine_text(nil, _zone), do: ""

  defp madeleine_text(%{bookmark: b}, zone) do
    "# A madeleine\n\nAdjacent to this and unheard for a while, surfaced by nearness and not by rank; whether it belongs here is mine to decide.\n\n##{b.number} #{Local.day(zone, b.anchor_at)}: #{b.line}" <>
      if(b.summary in [nil, ""], do: "", else: "\n#{b.summary}")
  end
end
