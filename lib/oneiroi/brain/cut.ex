defmodule Oneiroi.Brain.Cut do
  @moduledoc """
  Text at most so many characters, the rest cut with a note saying how
  much: a tool's answer as it enters a turn, a past one as a transcript
  replays it, a search hit's neighbourhood. Unbounded, a search that
  matched its own earlier answers grew to 2.4M characters, and a replayed
  turn asked a model for 1.9M tokens (2026-11-03).
  """

  @doc "`text` at most `limit` characters, with a note of how many more were cut."
  @spec cut(String.t(), non_neg_integer()) :: String.t()
  def cut(text, limit) when is_binary(text) do
    case String.length(text) - limit do
      over when over > 0 -> String.slice(text, 0, limit) <> "\n[cut: #{over} more characters]"
      _ -> text
    end
  end

  @doc """
  The words around the first case-insensitive `phrase` in `text`,
  `around` characters either side, marked where they were cut; the head
  of the text when the phrase is not in it.
  """
  @spec around(String.t(), String.t(), pos_integer()) :: String.t()
  def around(text, phrase, around) when is_binary(text) and is_binary(phrase) do
    graphemes = String.graphemes(text)
    lower = Enum.map(graphemes, &String.downcase/1)
    needle = phrase |> String.trim() |> String.downcase() |> String.graphemes()

    case needle != [] && find(lower, needle, 0) do
      at when is_integer(at) ->
        from = max(at - around, 0)
        upto = min(at + length(needle) + around, length(graphemes))
        middle = graphemes |> Enum.slice(from, upto - from) |> Enum.join()
        lead = if from > 0, do: "…", else: ""
        tail = if upto < length(graphemes), do: "…", else: ""
        lead <> middle <> tail

      _ ->
        cut(text, 2 * around)
    end
  end

  defp find([], _needle, _at), do: nil

  defp find([_ | rest] = list, needle, at) do
    if prefix?(list, needle), do: at, else: find(rest, needle, at + 1)
  end

  defp prefix?(_list, []), do: true
  defp prefix?([same | list], [same | needle]), do: prefix?(list, needle)
  defp prefix?(_list, _needle), do: false
end
