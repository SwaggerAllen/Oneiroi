defmodule Oneiroi.Brain.Compaction do
  @moduledoc """
  Compaction is ours (spec §5): when a session's messages since its last
  compaction reach `BRAIN_COMPACT_AFTER_MESSAGES`, the turn opens with a
  memory flush, where the resident, given the messages about to be
  summarised and its tools, bookmarks what it wants to keep; then a
  summary that never deletes history, recorded as `Compacted` on the
  session with the store sequence it covers. The live transcript the
  next turn sees is what follows that sequence, under the summary.

  Both calls go through the ledger as chat. A failure of either leaves
  the session as it was and the turn goes on uncompacted; the next turn
  tries again, since the count is still over the line. Nothing is logged
  about the content.
  """

  alias Oneiroi.Brain.History
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.{Request, Result}

  @doc "Compacts the turn's session if it has outgrown its window; `:ok`, `:skipped`, or the failure."
  @spec maybe(map()) :: :ok | :skipped | {:error, term()}
  def maybe(turn) do
    threshold = Config.fetch!(:brain, :compact_after_messages)

    case Kumbukumbu.uncompacted(turn.resident_id, turn.session_key) do
      {:ok, session, count} when count >= threshold -> compact(turn, session)
      _other -> :skipped
    end
  end

  defp compact(turn, session) do
    messages = Kumbukumbu.since_compaction(turn.resident_id, turn.session_key)
    through = messages |> Enum.map(& &1.sequence) |> Enum.max(fn -> 0 end)

    transcript = History.messages(messages)

    with :ok <- flush(turn, transcript),
         {:ok, summary} <- summarise(turn, session, History.words(messages)) do
      Kumbukumbu.compact(
        turn.resident_id,
        turn.session_key,
        turn.turn_ref,
        through,
        summary,
        turn.resident
      )
    end
  end

  # The flush is a tool round or two with the reply discarded: what it
  # produces is bookmarks, not words.
  defp flush(turn, transcript) do
    prompt = Prompt.message("memory_flush")
    messages = transcript ++ [prompt]
    rounds = Config.fetch!(:brain, :tool_rounds)
    loop(turn, messages, 0, rounds)
  end

  defp loop(turn, messages, round, rounds) do
    request = Request.new(turn.model, messages, tools: Tools.definitions())

    case Nisaba.call(turn.resident_id, :chat, request, turn.resident) do
      {:ok, %Result{tool_calls: [_ | _] = calls}} when round < rounds ->
        results =
          Enum.map(calls, fn call ->
            %{
              role: :tool,
              tool_call_id: call.id,
              content: Tools.run(call.name, call.arguments, turn)
            }
          end)

        assistant = %{
          role: :assistant,
          content: "",
          tool_calls:
            Enum.map(
              calls,
              &%{
                id: &1.id,
                type: "function",
                function: %{name: &1.name, arguments: Tools.wire_arguments(&1.arguments)}
              }
            )
        }

        loop(turn, messages ++ [assistant | results], round + 1, rounds)

      {:ok, %Result{}} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp summarise(turn, session, transcript) do
    previous =
      case session.summary do
        nil -> ""
        text -> "What you summarised before, to fold in:\n\n" <> text
      end

    prompt = Prompt.message("compaction", %{previous: previous})
    request = Request.new(turn.model, [prompt | transcript])

    case Nisaba.call(turn.resident_id, :chat, request, turn.resident) do
      {:ok, %Result{content: content}} when is_binary(content) and content != "" -> {:ok, content}
      {:ok, %Result{}} -> {:error, :summary_empty}
      {:error, reason} -> {:error, reason}
    end
  end
end
