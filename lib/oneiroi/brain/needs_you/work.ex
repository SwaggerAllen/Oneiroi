defmodule Oneiroi.Brain.NeedsYou.Work do
  @moduledoc """
  Sunna's work queue (brain#72). Two stages wait on him. A held item
  (`work_held`, brain#86, sunna#54): its next move is his, and its ask,
  in plain words, is the entry's subject, from the moment it was held
  until a move or a start clears it. And, from before sunna#42, an item
  blocked on a line of words rather than an item's number (`work_blocked`),
  since what it waited on was mostly him, until it is triaged. Blocked
  on a number is work waiting on work, the queue's and not his.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Sunna

  @impl true
  def stages,
    do: [%{kind: "work_held", screen: "work"}, %{kind: "work_blocked", screen: "work"}]

  @impl true
  def entries(resident_id) do
    for w <- Sunna.work_queue(resident_id).items, entry = entry(w), do: entry
  end

  defp entry(%{status: "held"} = w),
    do: %Entry{
      kind: "work_held",
      ref: w.number,
      since: w.held_at || w.moved_at || w.added_at,
      screen: "work",
      about: %{
        what: w.what,
        ask: w.held_ask,
        held_by: w.held_by,
        subject: "Work item ##{w.number} held: #{w.held_ask}"
      }
    }

  defp entry(%{status: "blocked"} = w) do
    unless item_ref?(w.blocked_on),
      do: %Entry{
        kind: "work_blocked",
        ref: w.number,
        since: w.moved_at || w.added_at,
        screen: "work",
        about: %{what: w.what, blocked_on: w.blocked_on}
      }
  end

  defp entry(_other), do: nil

  defp item_ref?(on), do: is_binary(on) and Regex.match?(~r/\A#\d+\z/, on)
end
