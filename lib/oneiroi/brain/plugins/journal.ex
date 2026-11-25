defmodule Oneiroi.Brain.Plugins.Journal do
  @moduledoc """
  Today's journal (spec §6.5, F29). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 3]

  alias Oneiroi.Brain.Pieces

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
    {text, rows} = Oneiroi.Seshat.journal_text_pieces(turn.resident_id)

    # Each row its own piece, by its own labels (kumbukumbu#111; Lily's
    # letter #1532 for why a row keeps them at all).
    "journal"
    |> section(
      text,
      "today's journal rows (spec §6.5, F29): the plan, notes, todos and wrap so far, rendered on this read"
    )
    |> Pieces.put(Pieces.rows(turn.resident_id, rows))
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
