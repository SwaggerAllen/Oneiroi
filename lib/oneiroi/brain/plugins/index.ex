defmodule Oneiroi.Brain.Plugins.Index do
  @moduledoc """
  The ranked index (kumbukumbu#46). A first-party plugin (brain#68): code that entered by review,
  under the same manifest as every plugin.
  """
  @behaviour Oneiroi.Brain.Plugin

  import Oneiroi.Brain.Plugin, only: [section: 4]

  @impl Oneiroi.Brain.Plugin
  def manifest,
    do: %{
      key: "index",
      name: "The bookmark index",
      about: "your bookmarks, ranked against the turn's words",
      place: :turn,
      reads: ~w(bookmarks retrieval)
    }

  @impl Oneiroi.Brain.Plugin
  def sections(_turn, %{index: index}) do
    section(
      "index",
      index.text,
      index_reason(index),
      %{
        tokens: index.tokens,
        text: index.text,
        # The ranked alone: the exploration's draws are its own slot.
        refs: index.included -- index.explored,
        seeds: index.seeds
      }
    )
  end

  # The near-miss record (spec §5, P6): the bookmarks the index ranked
  # and did not inject, each with the reason it lost, as injection rows
  # that carry no message and no `refs`, so a near-miss never counts as
  # indexed. Max: "the near-misses are where a character quietly bends."
  defp index_reason(%{considered: nil} = index),
    do:
      "the bookmark index by recency, no vector this turn: #{length(index.included)} listed, #{index.left_out} left out"

  defp index_reason(index),
    do:
      "the ranked index (kumbukumbu#46): #{index.considered} considered, #{length(index.included) - length(index.explored)} returned by rank, #{length(index.near_misses)} considered and not returned"

  @doc "The near-misses as injection rows: considered, never injected."
  def near_misses(index) do
    Enum.map(index.near_misses, fn m ->
      %{
        label: "near-miss",
        # Not `refs`, which would mark it indexed; read for what the
        # memory agent considered (`Oneiroi.Brain.Uses`) and not recorded
        # on the row.
        considered: [m.number],
        tokens: 0,
        reason: "considered and not injected: bookmark ##{m.number}, #{m.reason}",
        text: m.line
      }
    end)
  end
end
