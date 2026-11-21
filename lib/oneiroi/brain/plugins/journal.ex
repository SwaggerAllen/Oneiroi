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
    "journal"
    |> section(
      Oneiroi.Seshat.journal_text(turn.resident_id),
      "today's journal rows (spec §6.5, F29): the plan, notes, todos and wrap so far, rendered on this read"
    )
    |> Enum.map(&Map.put(&1, :labels, labels(turn.resident_id)))
  end

  # The section carries its rows' labels (kumbukumbu#84, Lily's letter
  # #1532).
  defp labels(resident_id) do
    case Oneiroi.Seshat.journal_day(resident_id, Oneiroi.Sunna.today(resident_id).day) do
      %{entries: entries} -> row_labels(entries)
      nil -> row_labels([])
    end
  end

  @doc """
  The labels of journal rows shown (kumbukumbu#84): every one each row's
  writing turn held; a row that kept none (written before) is
  unclassified; no rows is the common room's.
  """
  def row_labels([]), do: [%{"kind" => "common_room"}]

  def row_labels(rows),
    do:
      rows
      |> Enum.flat_map(&(Map.get(&1, :labels) || [%{"kind" => "unclassified"}]))
      |> Enum.uniq()
end
