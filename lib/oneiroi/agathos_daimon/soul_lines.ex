defmodule Oneiroi.AgathosDaimon.SoulLines do
  @moduledoc """
  The soul file as rows (spec §6.17, P39, the author's call): every
  paragraph of `SOUL.md` carries a stable, granular id minted from the
  resident's own sequence, so `<slug>:soul/<n>` survives a rebuild and a
  line's rewording keeps its id. Sections are too coarse and drift;
  inline ids in a whole-content file do not survive a hand edit, so the
  rows are the truth, the file is rendered from them (the journal's
  pattern), and a file written whole is split here and matched against
  the rows.

  Pure: the marker, the split, the render and the diff of a new text
  against the live lines. The aggregate applies the diff's verdict as
  events; the stored content is always the words without markers, so the
  log never carries a number the render can put back.
  """

  @marker ~r/\A(\s*)\[soul\/(\d+)\]\s*/
  @separator ~r/\n[ \t]*\n/

  @doc "A text with every paragraph's `[soul/n]` marker removed, so a rendered file written back is the words alone."
  @spec strip(String.t() | nil) :: String.t() | nil
  def strip(nil), do: nil

  def strip(text) when is_binary(text) do
    text
    |> String.split(@separator, include_captures: true)
    |> Enum.map_join(&String.replace(&1, @marker, "\\1"))
  end

  @doc """
  The lines of a text with the number each claims: its paragraphs,
  trimmed, blank ones and headings dropped (a heading names the file,
  not the resident; the card skips them for the same reason), each as
  `{number | nil, text}` with its marker read and stripped.
  """
  @spec marked(String.t() | nil) :: [{pos_integer() | nil, String.t()}]
  def marked(nil), do: []

  def marked(text) when is_binary(text) do
    text
    |> String.split(@separator)
    |> Enum.map(&claim/1)
    |> Enum.reject(fn {_n, p} -> p == "" or String.starts_with?(p, "#") end)
  end

  defp claim(paragraph) do
    case Regex.run(@marker, paragraph) do
      [_whole, _space, digits] ->
        {String.to_integer(digits), paragraph |> String.replace(@marker, "") |> String.trim()}

      nil ->
        {nil, String.trim(paragraph)}
    end
  end

  @doc "The lines of a text as words alone: `marked/1` without the claims."
  @spec paragraphs(String.t() | nil) :: [String.t()]
  def paragraphs(text), do: text |> marked() |> Enum.map(&elem(&1, 1))

  @doc "A line as the file renders it: its marker, then its words."
  @spec marker(pos_integer()) :: String.t()
  def marker(number), do: "[soul/#{number}] "

  @doc """
  The file rendered: the content as written, byte for byte, with each
  line's marker in front of its paragraph. The live lines are in the
  file's order and one per non-heading paragraph by construction, so the
  markers are dealt out in order; a text whose paragraphs do not match
  the lines (one not written through the aggregate) renders bare rather
  than wrongly numbered.
  """
  @spec render(String.t(), [%{number: pos_integer(), text: String.t()}]) :: String.t()
  def render(content, lines) when is_binary(content) do
    parts = String.split(content, @separator, include_captures: true)

    if paragraphs(content) == Enum.map(lines, & &1.text),
      do: deal(parts, lines),
      else: content
  end

  defp deal(parts, lines) do
    {out, _} =
      Enum.map_reduce(parts, lines, fn part, rest ->
        trimmed = String.trim(part)

        if trimmed == "" or String.starts_with?(trimmed, "#") or rest == [] do
          {part, rest}
        else
          [line | rest] = rest
          {String.replace(part, ~r/\A(\s*)/, "\\1" <> marker(line.number)), rest}
        end
      end)

    Enum.join(out)
  end

  @doc """
  The diff of a new text's lines (`marked/1`) against the live lines
  (`[{number, text}]` in order). A paragraph claiming a live line's
  number by its marker keeps that line, reworded when the words differ,
  which is how a rewording keeps its id; a paragraph without a marker,
  or with one that names no live line, keeps the first unclaimed live
  line with the same words, else is written new. A text with no markers
  at all (a seed, a hand edit, an import) has no way to claim, so there
  its new paragraphs pair with the unclaimed old lines in order instead
  of replacing them. Whatever is left unclaimed is retired. The result
  is the new order, each entry one of `{:kept, number}`,
  `{:reworded, number, text}` or `{:written, text}`, and the retired
  numbers.
  """
  @spec diff([{pos_integer(), String.t()}], [{pos_integer() | nil, String.t()}]) :: %{
          order: [
            {:kept, pos_integer()}
            | {:reworded, pos_integer(), String.t()}
            | {:written, String.t()}
          ],
          retired: [pos_integer()]
        }
  def diff(lines, marked) do
    {order, claimed} = Enum.map_reduce(marked, MapSet.new(), &place(&1, &2, lines))
    free_old = Enum.reject(lines, fn {m, _} -> MapSet.member?(claimed, m) end)

    {order, free_old} =
      if Enum.any?(marked, fn {n, _} -> n != nil end),
        do: {order, free_old},
        else: pair(order, free_old)

    %{order: order, retired: Enum.map(free_old, &elem(&1, 0))}
  end

  # One paragraph's place: by its claim when the claim is a live,
  # unclaimed number; else by its words; else new.
  defp place({n, text}, claimed, lines) do
    by_claim = n != nil and List.keymember?(lines, n, 0) and not MapSet.member?(claimed, n)

    cond do
      by_claim and List.keyfind(lines, n, 0) == {n, text} -> {{:kept, n}, MapSet.put(claimed, n)}
      by_claim -> {{:reworded, n, text}, MapSet.put(claimed, n)}
      true -> place_by_words(text, claimed, lines)
    end
  end

  defp place_by_words(text, claimed, lines) do
    case Enum.find(lines, fn {m, t} -> t == text and not MapSet.member?(claimed, m) end) do
      {m, _} -> {{:kept, m}, MapSet.put(claimed, m)}
      nil -> {{:written, text}, claimed}
    end
  end

  # The fallback for a text with no markers: the i-th new paragraph takes
  # the i-th unclaimed old line's number, so a marker-less rewording of a
  # line is still that line.
  defp pair(order, free_old) do
    Enum.map_reduce(order, free_old, fn
      {:written, text}, [{n, _} | rest] -> {{:reworded, n, text}, rest}
      entry, rest -> {entry, rest}
    end)
  end
end
