defmodule Oneiroi.Brain.Reactions do
  @moduledoc """
  The reacts' vocabulary and the line that tells them (kumbukumbu#56,
  brain#73). The vocabulary is `REACTIONS.md` at the root of her
  repository, a root document either party writes, one pair a line
  (`- 🔀 merged`), presented as the witness's palette and as the glosses
  on her line; until it exists the seed stands. What she is told is one
  line on her next turn, wherever it is: each react in order, glossed,
  with where it landed. A react is seen, never signed off: the line says
  so, and nothing in it closes anything.
  """

  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Seshat

  @file_name "REACTIONS.md"

  # The pairs the dyad uses (Lily's order #452), for his read.
  @seed [{"🔀", "merged"}, {"👁", "seen"}, {"⚜️", "warm"}, {"❤️", "loved"}]

  @doc "The vocabulary's file, at her repository's root."
  def file_name, do: @file_name

  @doc "The vocabulary: `[{emoji, meaning}]`, the file's, or the seed until it exists."
  def vocabulary(resident_id) do
    case Seshat.document(resident_id, @file_name) do
      {:ok, %{content: content}} -> parse(content)
      _absent -> @seed
    end
  end

  @doc "Reads `- <emoji> <meaning>` lines; anything else in the file is prose, kept and ignored."
  def parse(content) do
    for line <- String.split(content, "\n"),
        [_, emoji, meaning] <- [Regex.run(~r/^\s*[-*]\s+(\S+)\s+(?:[-:—]\s*)?(.+?)\s*$/u, line)],
        not String.match?(emoji, ~r/[\p{L}\p{N}]/u),
        do: {emoji, meaning}
  end

  @doc "Writes the vocabulary as the file, by either party."
  def set_vocabulary(resident_id, pairs, actor) do
    lines = Enum.map_join(pairs, "\n", fn {e, m} -> "- #{e} #{m}" end)

    content = """
    # Reactions

    What each react means between us (kumbukumbu#56): one pair a line,
    the emoji and then its meaning. Either of us edits this; a react is
    seen, never signed off.

    #{lines}
    """

    with {:ok, _} <- Seshat.write(resident_id, @file_name, content, actor), do: :ok
  end

  @doc "The line for the reacts not yet told her, and the last number in it; nil when there are none."
  def untold(resident_id, session_key) do
    case Kumbukumbu.reacts(resident_id, untold: true, by: "witness") do
      [] ->
        nil

      reacts ->
        said = %{
          gloss: Map.new(vocabulary(resident_id)),
          titles: titles(resident_id),
          zone: Local.zone(resident_id),
          here: session_key
        }

        {"Reacted since you last spoke (seen, never signed off; nothing here closes anything): " <>
           Enum.map_join(reacts, "; ", &part(&1, said)) <> ".", List.last(reacts).number}
    end
  end

  defp part(r, said) do
    meaning = if m = said.gloss[r.emoji], do: " (#{m})", else: ""

    "#{r.emoji}#{meaning} on #{where(r, said.here, said.titles)}, #{Local.stamp(said.zone, r.reacted_at)}"
  end

  defp where(%{target_kind: "letter", letter: n}, _here, _titles), do: "letter ##{n}"
  defp where(%{session_key: here}, here, _titles), do: "your reply in this conversation"

  defp where(%{session_key: key}, _here, titles),
    do: "your reply in #{Map.get(titles, key, "another conversation")}"

  defp titles(resident_id),
    do: Map.new(Kumbukumbu.sessions({:resident, resident_id}), &{&1.key, Conversation.title(&1)})
end
