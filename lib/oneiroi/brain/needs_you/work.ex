defmodule Oneiroi.Brain.NeedsYou.Work do
  @moduledoc """
  Sunna's work queue (brain#72). Blocked work waits on other work and is
  the queue's, not his (sunna#42, kept by the witness 2026-11-09): only
  an item blocked before that rule, its blocker a line of words rather
  than an item's number, shows here, since what it waited on was mostly
  him, until it is triaged.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Sunna

  @impl true
  def stages, do: [%{kind: "work_blocked", screen: "work"}]

  @impl true
  def entries(resident_id) do
    for w <- Sunna.work_queue(resident_id).items,
        w.status == "blocked",
        not item_ref?(w.blocked_on) do
      %Entry{
        kind: "work_blocked",
        ref: w.number,
        since: w.moved_at || w.added_at,
        screen: "work",
        about: %{what: w.what, blocked_on: w.blocked_on}
      }
    end
  end

  defp item_ref?(on), do: is_binary(on) and Regex.match?(~r/\A#\d+\z/, on)
end
