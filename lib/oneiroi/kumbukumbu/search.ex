defmodule Oneiroi.Kumbukumbu.Search do
  @moduledoc """
  Memory's halves of the one search (kumbukumbu#59): the words of the
  transcripts, the bookmarks by their line, summary and tags, and what
  her memory would surface for the words. The web layer interleaves
  them with the library's (seshat#53); each half ranks its own.

  None of them lists a private, unshared session's words (spec §6.3):
  the words half leaves its messages out in the query as well as by the
  policy, and the bookmarks a private session holds are left out of the
  other two, since a bookmark made there is its words too.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Kumbukumbu.Memories
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @doc "One page of a resident's messages holding `text` under `scope` (kumbukumbu#67): `Store.search_page/3`'s options and answer."
  @spec words_page(term(), String.t(), String.t(), keyword()) ::
          {[{Store.Message.t(), Store.Session.t()}], boolean()}
  def words_page(scope, resident_id, text, opts),
    do: Scope.run(scope, fn -> Store.search_page(resident_id, text, opts) end)

  @doc "One resident's messages holding `text` under `scope`, newest first, each `{message, session}`."
  @spec words(term(), String.t(), String.t(), pos_integer()) :: [
          {Store.Message.t(), Store.Session.t()}
        ]
  def words(scope, resident_id, text, limit),
    do: Scope.run(scope, fn -> Store.search_words(resident_id, text, limit) end)

  @doc """
  The bookmarks whose line, summary or tags hold `text`, case aside:
  a match in the line ranks above one in the summary, and that above a
  tag's, newest first within each. Each `%{bookmark, matched, score}`,
  the score 1.0, 0.67 or 0.33 by where it matched.
  """
  @spec bookmarks(String.t(), String.t(), pos_integer()) :: [map()]
  def bookmarks(resident_id, text, limit) do
    needle = text |> String.trim() |> String.downcase()
    withheld = withheld(resident_id)

    resident_id
    |> Memories.bookmarks()
    |> Enum.reject(&MapSet.member?(withheld, &1.session_key))
    |> Enum.flat_map(fn b ->
      case matched(b, needle) do
        nil -> []
        {field, score} -> [%{bookmark: b, matched: field, score: score}]
      end
    end)
    |> Enum.sort_by(&{-&1.score, -&1.bookmark.number})
    |> Enum.take(limit)
  end

  defp matched(b, needle) do
    cond do
      holds?(b.line, needle) -> {:line, 1.0}
      holds?(b.summary, needle) -> {:summary, 0.67}
      Enum.any?(b.tags || [], &holds?(&1, needle)) -> {:tags, 0.33}
      true -> nil
    end
  end

  defp holds?(text, needle) when is_binary(text),
    do: String.contains?(String.downcase(text), needle)

  defp holds?(_text, _needle), do: false

  @doc """
  What her memory would surface for `text` in the common room, as a turn
  of the main chat would be given it (kumbukumbu#46): the words embedded
  once (`memory_query/4`), the ranked index's returned lines in their
  order with their scores, then the madeleine past them. The random draw
  and the pins are left out: the draw is not about the words, and the
  pins are in front of every turn whatever is said. With ranked memory
  switched off, or no vector, the index is by recency and carries no
  score, as the turn's would. Each `%{bookmark, via, score}`, `via`
  `index` or `madeleine`.
  """
  @spec surfaced(String.t(), String.t(), Actor.t(), boolean(), pos_integer()) :: [map()]
  def surfaced(resident_id, text, %Actor{} = actor, ranked?, limit) do
    vector = Memories.memory_query(resident_id, text, actor)
    index = Memories.ranked_index(resident_id, nil, ranked? && vector)
    returned = index.included -- index.explored
    madeleine = Memories.madeleine_near(resident_id, vector, nil, index.included)
    rows = Map.new(Memories.bookmarks(resident_id), &{&1.number, &1})
    withheld = withheld(resident_id)

    listed =
      Enum.map(returned, &%{number: &1, via: :index, score: Map.get(index.scores, &1)}) ++
        if(madeleine,
          do: [%{number: madeleine.bookmark.number, via: :madeleine, score: nil}],
          else: []
        )

    listed
    |> Enum.flat_map(fn %{number: n} = l ->
      case rows[n] do
        nil -> []
        b -> [%{bookmark: b, via: l.via, score: l.score}]
      end
    end)
    |> Enum.reject(&MapSet.member?(withheld, &1.bookmark.session_key))
    |> Enum.take(limit)
  end

  # The keys of the resident's private sessions she has not shared.
  defp withheld(resident_id), do: Memories.locked_sessions(resident_id)
end
