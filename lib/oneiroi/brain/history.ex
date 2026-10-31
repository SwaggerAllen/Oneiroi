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
  """

  @roles %{"user" => :user, "assistant" => :assistant, "system" => :system}
  @record ~r/\A([A-Za-z0-9_-]+)\((.*?)\) -> (.*)\z/s

  @doc "The chat messages for stored rows, in order, every tool row a call and its answer."
  @spec messages([%{role: String.t(), content: String.t() | nil}]) :: [map()]
  def messages(rows) do
    rows
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {row, n} -> message(row, n) end)
  end

  @doc """
  The same rows for a request that offers no tools, the compaction's
  summary: a tool row goes back as the assistant's words. A call in a
  request without tools is a shape this codebase has not measured a
  provider accepting, and a summary has no use for one.
  """
  @spec words([%{role: String.t(), content: String.t() | nil}]) :: [map()]
  def words(rows) do
    Enum.map(rows, fn
      %{role: "tool", content: content} -> %{role: :assistant, content: content}
      %{role: role, content: content} -> %{role: Map.fetch!(@roles, role), content: content}
    end)
  end

  defp message(%{role: "tool", content: content}, n) do
    case Regex.run(@record, content || "") do
      [_all, name, arguments, output] ->
        id = "history_#{n}"
        call = %{id: id, type: "function", function: %{name: name, arguments: arguments}}

        [
          %{role: :assistant, content: "", tool_calls: [call]},
          %{role: :tool, tool_call_id: id, content: output}
        ]

      nil ->
        [%{role: :assistant, content: content}]
    end
  end

  defp message(%{role: role, content: content}, _n),
    do: [%{role: Map.fetch!(@roles, role), content: content}]
end
