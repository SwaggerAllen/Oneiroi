defmodule Oneiroi.Brain.FreeTime do
  @moduledoc """
  Her free time, remembered (brain#53, sunna#25): each run the schedule
  recorded, with the conversation it opened and what it did there. What
  a pass did is in its transcript already, as the tool calls it made;
  the writes among them (a document written, a bookmark added, a letter
  sent, a journal row) are the receipts, each in the platform's words of
  what was made, never hers. The resident reads the pass itself through
  `transcript_read`; the witness sees the receipts, since free time is
  private as to its words (spec §6.3, v0.2 P2).
  """

  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Sunna

  @receipt_chars 160

  @doc """
  The latest `limit` runs, newest first: day, slot, outcome, the
  conversation, its turns, and the writes it made, `writes` being the
  tool names that write (`Tools.writes/0`, passed in: the tools call
  this, so this cannot call them back).
  """
  @spec history(String.t(), pos_integer(), [String.t()]) :: [map()]
  def history(resident_id, limit, writes) do
    writes = writes |> MapSet.new() |> MapSet.delete("memory_feedback")

    resident_id
    |> Sunna.free_time_history(limit)
    |> Enum.map(&run(resident_id, &1, writes))
  end

  defp run(resident_id, %{session_key: key} = r, writes) when is_binary(key) do
    case Kumbukumbu.transcript({:resident, resident_id}, key) do
      {:ok, _session, messages} ->
        Map.merge(base(r), %{
          turns: messages |> Enum.map(& &1.turn_ref) |> Enum.uniq() |> length(),
          did: receipts(messages, writes)
        })

      _absent ->
        Map.merge(base(r), %{turns: 0, did: []})
    end
  end

  defp run(_resident_id, r, _writes), do: Map.merge(base(r), %{turns: 0, did: []})

  defp base(r),
    do: %{day: r.day, slot: r.slot, outcome: r.outcome, session_key: r.session_key, at: r.at}

  # A captured tool call reads `name(arguments) -> output`; a write's
  # output is the platform's line saying what it made.
  defp receipts(messages, writes) do
    for %{role: "tool", content: content} <- messages,
        [_, name, output] <- [Regex.run(~r/\A([a-z_]+)\(.*?\) -> (.*)\z/s, content || "")],
        MapSet.member?(writes, name) do
      %{
        tool: name,
        result: output |> String.split("\n") |> hd() |> String.slice(0, @receipt_chars)
      }
    end
  end
end
