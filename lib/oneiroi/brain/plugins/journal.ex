defmodule Oneiroi.Brain.Plugins.Journal do
  @moduledoc """
  Today's journal (spec §6.5, F29). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "journal",
      name: "Today's journal",
      about: "today's journal rows: the plan, notes, todos and wrap so far",
      place: :turn,
      reads: ~w(journal)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(turn, _ctx) do
    section(
      "journal",
      Oneiroi.Seshat.journal_text(turn.resident_id),
      "today's journal rows (spec §6.5, F29): the plan, notes, todos and wrap so far, rendered on this read"
    )
  end
end
