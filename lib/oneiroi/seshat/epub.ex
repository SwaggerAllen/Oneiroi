defmodule Oneiroi.Seshat.Epub do
  @moduledoc """
  A DRM-free EPUB read into a book's facts and its chapters as plain
  markdown (seshat#98; Lily's `design/reading-library-build.md` §1,
  "chapter-aware segmentation before reading begins"). Pure: the bytes
  in, `{:ok, book}` or `{:error, reason}` out, nothing on disk.

  An EPUB is a zip: `META-INF/container.xml` names the package (the
  OPF), whose metadata gives the title, author and identifier, whose
  manifest names every file and whose spine gives the reading order. Each
  spine item that is a page of text becomes a chapter, its markup turned
  into markdown (headings, paragraphs, emphasis, lists, quotations kept;
  images and styling dropped); a page with no words (a cover, an image
  plate) is left out. The OPF is read with patterns rather than an XML
  parser, so a file the platform did not write never reaches one, and
  nothing new is added to the release for it.

  Bounded: at most `@max_entries` files and `@max_bytes` unpacked, so an
  archive that unpacks to far more than it weighs is refused before it is
  read.
  """

  alias Oneiroi.Seshat.Error

  @max_entries 5_000
  @max_bytes 200 * 1024 * 1024
  @text_types ~w(application/xhtml+xml text/html application/xml)

  @type chapter :: %{title: String.t() | nil, text: String.t()}
  @type book :: %{
          title: String.t(),
          author: String.t() | nil,
          identifier: String.t() | nil,
          publisher: String.t() | nil,
          date: String.t() | nil,
          language: String.t() | nil,
          chapters: [chapter()]
        }

  @doc "The book in an EPUB's bytes, or why it could not be read: `seshat_book_invalid` with the reason in its details."
  @spec parse(binary()) :: {:ok, book()} | {:error, Error.t()}
  def parse(bytes) do
    case read(bytes) do
      {:ok, book} ->
        {:ok, book}

      {:unreadable, why} ->
        {:error, Error.new(:seshat_book_invalid, :seshat_epub_unreadable, reason: why)}
    end
  end

  defp read(bytes) when is_binary(bytes) do
    with {:ok, files} <- unzip(bytes),
         {:ok, opf_path} <- rootfile(files),
         {:ok, opf} <- fetch(files, opf_path),
         meta = metadata(opf),
         {:ok, title} <- title(meta),
         chapters = chapters(files, opf, Path.dirname(opf_path)),
         :ok <- some(chapters) do
      {:ok, meta |> Map.delete(:raw_title) |> Map.merge(%{title: title, chapters: chapters})}
    end
  end

  defp read(_other), do: {:unreadable, "the upload is not a file"}

  # ---- the archive ----

  defp unzip(bytes) do
    with {:ok, entries} <- list(bytes),
         :ok <- bounded(entries),
         {:ok, files} <- :zip.unzip(bytes, [:memory]) do
      {:ok, Map.new(files, fn {name, data} -> {to_string(name), data} end)}
    else
      {:unreadable, _why} = unreadable -> unreadable
      _broken -> {:unreadable, "the file is not an EPUB (it is not a readable zip)"}
    end
  end

  defp list(bytes) do
    case :zip.list_dir(bytes) do
      {:ok, [_comment | entries]} ->
        {:ok, for({:zip_file, _, info, _, _, _} <- entries, do: info)}

      _broken ->
        {:unreadable, "the file is not an EPUB (it is not a readable zip)"}
    end
  end

  defp bounded(infos) do
    total = infos |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    cond do
      length(infos) > @max_entries ->
        {:unreadable, "the EPUB holds more than #{@max_entries} files"}

      total > @max_bytes ->
        {:unreadable, "the EPUB unpacks to more than #{div(@max_bytes, 1_048_576)} MB"}

      true ->
        :ok
    end
  end

  defp fetch(files, path) do
    case Map.fetch(files, path) do
      {:ok, data} -> {:ok, data}
      :error -> {:unreadable, "the EPUB names #{path}, which it does not hold"}
    end
  end

  defp rootfile(files) do
    with {:ok, container} <- fetch(files, "META-INF/container.xml"),
         [_, path] <-
           Regex.run(~r/<rootfile\b[^>]*\bfull-path\s*=\s*["']([^"']+)["']/i, container) do
      {:ok, normalize(path)}
    else
      {:unreadable, _} -> {:unreadable, "the file is not an EPUB (no META-INF/container.xml)"}
      nil -> {:unreadable, "the EPUB's container names no package"}
    end
  end

  # ---- the package ----

  defp metadata(opf) do
    %{
      author: dc(opf, "creator"),
      identifier: identifier(opf),
      publisher: dc(opf, "publisher"),
      date: dc(opf, "date"),
      language: dc(opf, "language")
    }
    |> Map.put(:raw_title, dc(opf, "title"))
  end

  defp title(%{raw_title: t}) when is_binary(t) and t != "", do: {:ok, t}
  defp title(_meta), do: {:unreadable, "the EPUB's package gives no title"}

  defp dc(opf, name) do
    case Regex.run(~r/<dc:#{name}\b[^>]*>(.*?)<\/dc:#{name}>/is, opf) do
      [_, value] -> value |> text_of() |> blank()
      nil -> nil
    end
  end

  # The package's own identifier (unique-identifier names it), else the
  # first; what a re-import of the same edition is known by.
  defp identifier(opf) do
    by_id =
      with [_, id] <-
             Regex.run(~r/<package\b[^>]*\bunique-identifier\s*=\s*["']([^"']+)["']/i, opf),
           [_, value] <-
             Regex.run(
               ~r/<dc:identifier\b[^>]*\bid\s*=\s*["']#{Regex.escape(id)}["'][^>]*>(.*?)<\/dc:identifier>/is,
               opf
             ) do
        value |> text_of() |> blank()
      else
        _none -> nil
      end

    by_id || dc(opf, "identifier")
  end

  defp chapters(files, opf, base) do
    items = manifest(opf)

    for idref <- spine(opf),
        %{href: href, type: type} <- [Map.get(items, idref)],
        type in @text_types,
        {:ok, page} <- [fetch(files, resolve(base, href))],
        text = markdown(page),
        text != "" do
      %{title: heading(text), text: text}
    end
  end

  defp some([]), do: {:unreadable, "the EPUB has no chapter with words in it"}
  defp some(_chapters), do: :ok

  defp manifest(opf) do
    for [tag] <- Regex.scan(~r/<item\b[^>]*>/is, opf),
        attrs = attributes(tag),
        id = attrs["id"],
        href = attrs["href"],
        id != nil and href != nil,
        into: %{},
        do: {id, %{href: URI.decode(href), type: attrs["media-type"]}}
  end

  defp spine(opf) do
    case Regex.run(~r/<spine\b[^>]*>(.*?)<\/spine>/is, opf) do
      [_, body] ->
        for [tag] <- Regex.scan(~r/<itemref\b[^>]*>/is, body),
            attrs = attributes(tag),
            attrs["linear"] != "no",
            is_binary(attrs["idref"]),
            do: attrs["idref"]

      nil ->
        []
    end
  end

  defp attributes(tag) do
    # An unmatched last group is left off the match, so a double-quoted
    # value comes back as three parts and a single-quoted one as four.
    for match <- Regex.scan(~r/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/, tag),
        into: %{},
        do: attribute(match)
  end

  defp attribute([_, name, dq]), do: {String.downcase(name), dq}
  defp attribute([_, name, _dq, sq]), do: {String.downcase(name), sq}

  # A manifest href is relative to the package's folder; `..` is folded
  # against it so the name matches the zip's entry.
  defp resolve(".", href), do: normalize(href)
  defp resolve(base, href), do: normalize(base <> "/" <> href)

  defp normalize(path) do
    path
    |> String.split("#", parts: 2)
    |> hd()
    |> String.split("/")
    |> Enum.reduce([], fn
      "..", [_ | rest] -> rest
      "..", [] -> []
      ".", acc -> acc
      "", acc -> acc
      seg, acc -> [seg | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("/")
  end

  # ---- a page as markdown ----

  @doc "A page of XHTML as markdown: headings, paragraphs, emphasis, lists and quotations kept; the rest is its words."
  @spec markdown(binary()) :: String.t()
  def markdown(page) do
    page
    |> body()
    |> String.replace(~r/<(script|style|head|svg)\b.*?<\/\1>/is, "")
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.replace(~r/\s+/u, " ")
    |> blocks()
    |> String.replace(~r/<[^>]*>/s, "")
    |> decode()
    |> tidy()
  end

  defp body(page) do
    case Regex.run(~r/<body\b[^>]*>(.*)<\/body>/is, page) do
      [_, inner] -> inner
      nil -> page
    end
  end

  defp blocks(html) do
    html
    |> String.replace(~r/<blockquote\b[^>]*>(.*?)<\/blockquote>/is, &quoted/1)
    |> String.replace(~r/<h([1-6])\b[^>]*>(.*?)<\/h\1>/is, fn whole ->
      [_, n, inner] = Regex.run(~r/<h([1-6])\b[^>]*>(.*?)<\/h\1>/is, whole)

      case String.trim(strip(inner)) do
        "" -> "\n\n"
        words -> "\n\n" <> String.duplicate("#", String.to_integer(n)) <> " " <> words <> "\n\n"
      end
    end)
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<li\b[^>]*>/i, "\n- ")
    |> String.replace(~r/<hr\b[^>]*>/i, "\n\n---\n\n")
    |> String.replace(
      ~r/<\/?(p|div|section|article|blockquote|ul|ol|table|tr|figure|aside|header|footer|nav|dl|dd|dt|pre)\b[^>]*>/i,
      "\n\n"
    )
    |> String.replace(~r/<(em|i|cite)\b[^>]*>(.*?)<\/\1>/is, "*\\2*")
    |> String.replace(~r/<(strong|b)\b[^>]*>(.*?)<\/\1>/is, "**\\2**")
  end

  # A quotation's own paragraphs, each line of them marked as quoted.
  defp quoted(whole) do
    [_, inner] = Regex.run(~r/<blockquote\b[^>]*>(.*?)<\/blockquote>/is, whole)

    lines =
      inner
      |> blocks()
      |> strip()
      |> tidy()
      |> String.split("\n")
      |> Enum.map_join("\n", &String.trim_trailing("> " <> &1))

    "\n\n" <> lines <> "\n\n"
  end

  defp strip(html), do: String.replace(html, ~r/<[^>]*>/s, "")

  defp tidy(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim/1)
    |> String.replace(~r/\*\*\s*\*\*|\*\s+\*/, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp heading(text) do
    case Regex.run(~r/^\#{1,6} (.+)$/m, text) do
      [_, title] -> title |> String.trim() |> blank()
      nil -> nil
    end
  end

  defp text_of(value),
    do: value |> strip() |> decode() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp blank(""), do: nil
  defp blank(value), do: value

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "mdash" => "—",
    "ndash" => "–",
    "hellip" => "…",
    "lsquo" => "‘",
    "rsquo" => "’",
    "ldquo" => "“",
    "rdquo" => "”",
    "copy" => "©",
    "eacute" => "é",
    "egrave" => "è",
    "aacute" => "á",
    "agrave" => "à",
    "ccedil" => "ç",
    "ouml" => "ö",
    "uuml" => "ü",
    "auml" => "ä",
    "shy" => ""
  }

  defp decode(text) do
    Regex.replace(~r/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/, text, fn whole, code ->
      case code do
        "#x" <> hex -> codepoint(String.to_integer(hex, 16), whole)
        "#" <> dec -> codepoint(String.to_integer(dec), whole)
        name -> Map.get(@entities, name, whole)
      end
    end)
  end

  # A number that names no character (a surrogate, past the last plane)
  # is left as written.
  defp codepoint(n, _whole) when n in 0..0xD7FF or n in 0xE000..0x10FFFF, do: <<n::utf8>>
  defp codepoint(_n, whole), do: whole
end
