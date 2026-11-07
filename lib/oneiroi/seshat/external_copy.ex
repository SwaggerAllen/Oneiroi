defmodule Oneiroi.Seshat.ExternalCopy do
  @moduledoc """
  Reading an external source's copy (seshat#46): the source a citation
  names, its latest copy from the repository, and the section an anchor
  names in it. A leaf: the citation resolver reads through here, and
  nothing here writes, so the resolver never reaches the document
  writes that index and cite in turn.
  """

  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian

  @doc "One external source by its citation's kind and ref (the anchor after `#` ignored), or nil."
  def by_citation(resident_id, kind, ref) when kind in ["web", "doc"] do
    key = ref |> String.split("#") |> hd()

    case Scope.resident(resident_id, fn -> Store.external_by_key(key) end) do
      %{kind: ^kind} = row -> row
      _other -> nil
    end
  end

  def by_citation(_resident_id, _kind, _ref), do: nil

  @doc """
  The copy of a cited source, whole or the section an anchor names:
  `{:ok, %{external, text, found}}`, where `found` says how the anchor
  was matched (`:whole`, `:heading`, `:near`, `:passage`, `:missing`).
  """
  def read(resident_id, kind, ref) do
    anchor =
      case String.split(ref, "#", parts: 2) do
        [_key, a] when a != "" -> a
        _none -> nil
      end

    with %Store.External{} = row <- by_citation(resident_id, kind, ref) || absent(ref),
         path when is_binary(path) <- row.path,
         {:ok, content} <- file(resident_id, path) do
      {found, text} = section(body(content), anchor)
      {:ok, %{external: row, text: text, found: found}}
    else
      # A source commissioned whose first copy has not landed.
      nil ->
        {:error, Error.new(:seshat_external_not_fetched, :seshat_externals_read_unfetched)}

      other ->
        other
    end
  end

  @doc "The copy's words without its frontmatter."
  @spec body(String.t()) :: String.t()
  def body("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [_front, body] -> String.trim_leading(body)
      [_unclosed] -> rest
    end
  end

  def body(text), do: text

  @doc """
  The section an anchor names in a markdown text: by a heading's slug
  or `{#id}`, then the nearest heading holding its words, then the
  passage holding them; `{how, text}`.
  """
  @spec section(String.t(), String.t() | nil) :: {atom(), String.t()}
  def section(text, nil), do: {:whole, text}

  def section(text, anchor) do
    lines = String.split(text, "\n")
    headings = headings(lines)
    wanted = slugify(anchor)
    words = anchor |> String.downcase() |> String.split(~r/[-_\s]+/, trim: true)

    exact = Enum.find(headings, &(&1.slug == wanted or &1.id == anchor))
    near = words != [] && Enum.find(headings, fn h -> Enum.all?(words, &(h.slug =~ &1)) end)

    cond do
      exact -> {:heading, cut(lines, exact, headings)}
      near -> {:near, cut(lines, near, headings)}
      p = passage(text, words) -> {:passage, p}
      true -> {:missing, text}
    end
  end

  defp headings(lines) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, i} ->
      case Regex.run(~r/\A(\#{1,6})\s+(.+?)\s*(?:\{#([A-Za-z0-9_.:-]+)\})?\s*\z/, line) do
        [_, hashes, title | id] ->
          [%{at: i, level: String.length(hashes), slug: slugify(title), id: List.first(id)}]

        nil ->
          []
      end
    end)
  end

  defp cut(lines, h, headings) do
    stop =
      Enum.find_value(headings, length(lines), fn other ->
        if other.at > h.at and other.level <= h.level, do: other.at
      end)

    lines |> Enum.slice(h.at, stop - h.at) |> Enum.join("\n") |> String.trim_trailing()
  end

  defp passage(_text, []), do: nil

  defp passage(text, words) do
    phrase = Enum.join(words, " ")

    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.find(&(&1 |> String.downcase() |> String.replace(~r/\s+/, " ") =~ phrase))
  end

  @doc "A heading's slug as GitHub makes it: lower case, punctuation dropped, spaces to `-`."
  @spec slugify(String.t()) :: String.t()
  def slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s_-]/u, "")
    |> String.trim()
    |> String.replace(~r/\s/, "-")
  end

  # The copy's file, read from the resident's repository at the path the
  # library registered for it; the path is the store's, never a caller's.
  # sobelow_skip ["Traversal.FileModule"]
  defp file(resident_id, path) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      case File.read(Path.join(dir, path)) do
        {:ok, content} ->
          {:ok, content}

        {:error, reason} ->
          {:error,
           Error.caught(:seshat_no_such_file, :seshat_external_copy_read, reason, path: path)}
      end
    end
  end

  defp absent(what),
    do:
      {:error,
       Error.new(:seshat_no_such_external, :seshat_external_copy_absent, what: to_string(what))}
end
