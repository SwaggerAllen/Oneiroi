defmodule Oneiroi.Brain.History do
  @moduledoc """
  A session's stored messages as a model reads them again: the turn's
  transcript and the compaction's both come through here.

  A tool's use is stored as one `tool` row, `name(arguments) -> output`
  (`Oneiroi.Brain.Turn`'s capture), and sent back as the pair the chat
  format requires: an assistant message calling the tool, then the
  `tool` message answering that call by its id. Sent bare, as it once
  was, a `tool` message answers no call, and the provider refuses the
  whole request: the fixture's turn 2 used four tools and turns 3 to 12
  each failed `nisaba_request_refused` in under a second.

  The ids are made here, unique within the request and of the alphabet
  every provider accepts; the provider's own ids were never stored. A
  row that does not read as `name(arguments) -> output` goes back as the
  assistant's words, which no provider refuses.

  Given the resident's zone, every message carries when it was said,
  inline at its head, `[2026-11-06 10:54 PST] `, the form her
  `transcript_read` shows (brain#58; the witness, 2026-11-06: the time
  belongs inline with the message, where the resident reads it). A tool
  call's stamp is on its answer. An inferred instant (kumbukumbu#50)
  reads `[time unknown]`, never the stand-in.
  """

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Brain.Cut
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Config

  @roles %{"user" => :user, "assistant" => :assistant, "system" => :system}
  @record ~r/\A([A-Za-z0-9_-]+)\((.*?)\) -> (.*)\z/s

  @doc "The chat messages for stored rows, in order, every tool row a call and its answer."
  @spec messages([%{role: String.t(), content: String.t() | nil}], String.t() | nil) :: [map()]
  def messages(rows, zone \\ nil) do
    rows
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {row, n} -> message(row, n, zone) end)
  end

  @doc """
  The zone the transcript is stamped in, or nil when the inline stamps
  are off (`BRAIN_HISTORY_STAMPS`, brain#59): off, nothing is stamped.
  """
  @spec zone(String.t()) :: String.t() | nil
  def zone(resident_id),
    do: if(Config.fetch!(:brain, :history_stamps), do: Local.zone(resident_id), else: nil)

  @doc "The prompt's line about the stamps, when they are on; empty when off."
  @spec stamps_line() :: String.t()
  def stamps_line do
    if Config.fetch!(:brain, :history_stamps),
      do:
        "\n\nWhere a message in the conversation begins with a time in brackets, like [2026-11-06 10:54 PST], the platform put it there: it is when that message was said, in your zone, and [time unknown] means the record has no time for it. Don't write one on your own replies; yours is added when it is kept.",
      else: ""
  end

  @doc """
  The stamp a message is shown under in `zone`: `[2026-11-06 10:54 PST] `,
  `[time unknown] ` for an inferred instant, and nothing with no zone or
  no instant.
  """
  @spec stamp(map(), String.t() | nil) :: String.t()
  def stamp(_row, nil), do: ""
  def stamp(%{instant_inferred: true}, _zone), do: "[time unknown] "
  def stamp(%{sent_at: %DateTime{} = at}, zone), do: "[#{Local.stamp(zone, at)}] "
  def stamp(_row, _zone), do: ""

  @stamped ~r/\A\s*\[(?:\d{4}-\d{2}-\d{2} \d{2}:\d{2} [A-Za-z0-9+:-]+|time unknown)\]\s*/

  @doc """
  A reply with the stamp taken off its head: the platform puts the time
  on every message, so one the model wrote itself, copying the form it
  reads, is not kept as its words (it would read twice, and could be a
  time it made up).
  """
  @spec unstamp(String.t() | nil) :: String.t() | nil
  def unstamp(nil), do: nil
  def unstamp(text), do: Regex.replace(@stamped, text, "", global: false)

  @doc """
  The same rows for a request that offers no tools, the compaction's
  summary: a tool row goes back as the assistant's words. A call in a
  request without tools is a shape this codebase has not measured a
  provider accepting, and a summary has no use for one.
  """
  @spec words([%{role: String.t(), content: String.t() | nil}], String.t() | nil) :: [map()]
  def words(rows, zone \\ nil) do
    Enum.map(rows, fn
      %{role: "tool", content: content} = row ->
        %{role: :assistant, content: stamp(row, zone) <> past(content || "")}

      %{role: role, content: content} = row ->
        %{role: Map.fetch!(@roles, role), content: stamped(row, content, zone)}
    end)
  end

  defp message(%{role: "tool", content: content} = row, n, zone) do
    case Regex.run(@record, content || "") do
      [_all, name, arguments, output] ->
        id = "history_#{n}"

        call = %{
          id: id,
          type: "function",
          function: %{name: name, arguments: Tools.wire_arguments(arguments)}
        }

        [
          %{role: :assistant, content: "", tool_calls: [call]},
          %{role: :tool, tool_call_id: id, content: stamp(row, zone) <> past(output)}
        ]

      nil ->
        [%{role: :assistant, content: stamp(row, zone) <> past(content || "")}]
    end
  end

  defp message(%{role: role, content: content} = row, _n, zone),
    do: [%{role: Map.fetch!(@roles, role), content: stamped(row, content, zone)}]

  # A message with no words keeps none: a stamp alone is not a message.
  defp stamped(_row, content, _zone) when content in [nil, ""], do: content
  defp stamped(row, content, zone), do: stamp(row, zone) <> content

  # A past tool answer replays as its head: what was looked at, not all
  # of what came back.
  defp past(text), do: Cut.cut(text, Config.fetch!(:brain, :history_tool_chars))
end
