defmodule Oneiroi.Kumbukumbu.Index do
  @moduledoc """
  The bookmark index the brain is shown every turn (spec §6.3, F7), built
  from the bookmark rows under a token budget, pure.

  Pins first, newest first, taking at most half the budget; then the rest
  by weight and then recency until the budget is spent. The text ends by
  saying how many were left out, because an index that looks complete
  and is not is the one failure this rule exists to prevent. Tokens are
  estimated at four bytes a token, as every estimate in the brain is.
  """

  @bytes_per_token 4

  @type built :: %{
          text: String.t(),
          included: [pos_integer()],
          left_out: non_neg_integer(),
          near_misses: [%{number: pos_integer(), line: String.t(), reason: String.t()}],
          tokens: non_neg_integer()
        }

  @doc "The index over `bookmarks` (each with `tags` loaded) within `budget` tokens."
  @spec build([map()], pos_integer()) :: built()
  def build(bookmarks, budget) when is_list(bookmarks) and is_integer(budget) and budget > 0 do
    {pinned, rest} = Enum.split_with(bookmarks, &pinned?/1)
    pinned = Enum.sort_by(pinned, & &1.number, :desc)
    rest = Enum.sort_by(rest, &{-&1.weight, -&1.number})

    {pinned_lines, pinned_tokens, pinned_out} = take(pinned, div(budget, 2))
    {rest_lines, _rest_tokens, rest_out} = take(rest, budget - pinned_tokens)

    included = Enum.map(pinned_lines ++ rest_lines, &elem(&1, 0))
    left_out = length(bookmarks) - length(included)
    lines = Enum.map(pinned_lines ++ rest_lines, &elem(&1, 1))

    # The near-miss record (spec §5, P6): every bookmark ranked and not
    # taken, in rank order, with the reason it lost, so the brain's
    # inspector can show what the index chose not to draw on.
    near_misses =
      Enum.map(pinned_out, fn {b, text} ->
        %{
          number: b.number,
          line: text,
          reason: "pinned, but the pins' half of the budget was spent"
        }
      end) ++
        Enum.map(rest_out, fn {b, text} ->
          %{
            number: b.number,
            line: text,
            reason:
              "ranked at weight #{Float.round(b.weight * 1.0, 3)} below what the budget held"
          }
        end)

    footer =
      case left_out do
        0 ->
          "Every bookmark is listed."

        n ->
          "#{n} more not shown; bookmark_open(number) reads any, and transcript_search reaches past the index."
      end

    text = Enum.join(lines ++ [footer], "\n")

    %{
      text: text,
      included: included,
      left_out: left_out,
      near_misses: near_misses,
      tokens: tokens(text)
    }
  end

  @doc "One bookmark's index line: number, day, pin, tags and the resident's line."
  @spec line(map()) :: String.t()
  def line(b) do
    tags = if b.tags == [], do: "", else: " [" <> Enum.join(b.tags, ", ") <> "]"
    pin = if pinned?(b), do: " (pinned)", else: ""
    "##{b.number} #{Date.to_iso8601(DateTime.to_date(b.anchor_at))}#{pin}#{tags} #{b.line}"
  end

  @doc "Tokens a text is estimated at: four bytes a token."
  @spec tokens(String.t()) :: non_neg_integer()
  def tokens(text), do: div(byte_size(text) + @bytes_per_token - 1, @bytes_per_token)

  defp pinned?(b), do: b.pinned_at != nil

  # Lines in order until the next would not fit; a line that does not fit
  # does not stop a shorter one after it from being tried, since the
  # order is a ranking and not a queue.
  defp take(bookmarks, budget) do
    Enum.reduce(bookmarks, {[], 0, []}, fn b, {lines, used, out} ->
      text = line(b)
      cost = tokens(text)

      if used + cost <= budget,
        do: {lines ++ [{b.number, text}], used + cost, out},
        else: {lines, used, out ++ [{b, text}]}
    end)
  end
end
