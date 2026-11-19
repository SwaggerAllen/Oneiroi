defmodule Oneiroi.Seshat.Books do
  @moduledoc """
  The resident's reading library (seshat#98; Lily's
  `design/reading-library-build.md` @8f033e7f411e, Scarlett's
  requirements). One import is one folder, `books/<slug>/`: the
  manifest (the book's facts and its chapters), each chapter a document,
  and `history.md`, what she read and peeked at, rendered from its rows
  after every reading.

  **Three states, from the history, never from her place.** A chapter is
  unread (no row), exposed (a peek: `library_read` by its path) or read
  (`book_read`). Her place (`current`) moves only when a read advances
  it, in either direction, and says where she is, not what she has read:
  reading chapter 40 out of order marks chapter 40 and nothing else.

  **The unread floor.** A chapter not read is dark to every search: the
  index embeds it nowhere (`Store.dark_chapters/0`), so no search, recall
  or citation hands it to her. Reading it by its path always works and is
  recorded as exposure, which leaves it dark. `book_read` lights it: the
  read row, then the index again. The repository carries every chapter
  whatever its state, so the export does too.

  **Hers.** Nothing under `books/` is published or copied to the house
  (`Published`, `Household`); the book itself is shared only by promotion, which
  waits for the citation traversal and is not built.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Epub
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Router
  alias Oneiroi.Seshat.Store

  @rights ~w(public-domain house-shareable purchased-drm-free)

  @doc "The rights notes a book is imported under: public-domain, house-shareable, purchased-drm-free."
  def rights, do: @rights

  # ---- import ----

  @doc """
  A book imported from an EPUB's bytes, by its witness: parsed, its
  chapters written under `books/<slug>/` in one commit with its manifest
  and an empty history. `attrs`: `rights` (required, one of `rights/0`),
  `caveat` and `source` (what the file was called), both optional. The
  same edition again is refused with where it is.
  """
  def import(resident_id, bytes, attrs, %Actor{kind: :witness} = actor) do
    rights = attrs["rights"]

    with :ok <- rights_ok(rights),
         {:ok, epub} <- Epub.parse(bytes),
         slug = slug_for(resident_id, epub.title),
         units = units(epub.chapters),
         {:ok, _events} <-
           dispatch(%Commands.ImportBook{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             slug: slug,
             title: epub.title,
             author: epub.author,
             identifier: epub.identifier,
             rights: rights,
             caveat: blank(attrs["caveat"]),
             units: Enum.map(units, & &1.id),
             titles: Enum.map(units, & &1.title)
           }),
         {:ok, _written} <-
           Documents.write_all(
             resident_id,
             files(slug, epub, units, attrs, rights),
             actor,
             "Import a book: #{epub.title}"
           ) do
      {:ok, Scope.resident(resident_id, fn -> Store.book(slug) end)}
    end
  end

  def import(_resident_id, _bytes, _attrs, _actor),
    do: {:error, Error.new(:seshat_book_invalid, :seshat_books_import_witness)}

  defp rights_ok(rights) when rights in @rights, do: :ok

  defp rights_ok(_rights),
    do: {:error, Error.new(:seshat_book_invalid, :seshat_books_import_rights)}

  # The title's words as a folder name; a second book of the same title
  # (another edition) takes the next number.
  defp slug_for(resident_id, title) do
    base =
      title
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 60)
      |> String.trim("-")
      |> case do
        "" -> "book"
        slug -> slug
      end

    taken = MapSet.new(Scope.resident(resident_id, fn -> Store.books() end), & &1.slug)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  # Each chapter a unit, numbered in reading order; one too large for a
  # document is split at its paragraphs into parts.
  defp units(chapters) do
    limit = Config.fetch!(:seshat, :document_bytes) - 2_048
    width = max(3, chapters |> length() |> Integer.to_string() |> String.length())

    chapters
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {chapter, i} ->
      id = i |> Integer.to_string() |> String.pad_leading(width, "0")
      title = chapter.title || "Section #{i}"

      text =
        if String.starts_with?(chapter.text, "#"),
          do: chapter.text,
          else: "# #{title}\n\n" <> chapter.text

      parts(id, title, split(text, limit))
    end)
  end

  defp parts(id, title, [one]), do: [%{id: id, title: title, text: one}]

  defp parts(id, title, parts) do
    for {part, n} <- Enum.with_index(parts, 1),
        do: %{id: "#{id}-#{n}", title: "#{title} (part #{n})", text: part}
  end

  defp split(text, limit) when byte_size(text) <= limit, do: [text]

  defp split(text, limit) do
    text
    |> String.split("\n\n")
    |> Enum.reduce([""], &gather(&1, &2, limit))
    |> Enum.reverse()
  end

  defp gather(para, ["" | done], _limit), do: [para | done]

  defp gather(para, [current | done], limit) do
    if byte_size(current) + byte_size(para) + 2 > limit,
      do: [para, current | done],
      else: [current <> "\n\n" <> para | done]
  end

  defp files(slug, epub, units, attrs, rights) do
    chapters = for u <- units, do: {"books/#{slug}/chapters/#{u.id}.md", u.text <> "\n"}

    [
      {"books/#{slug}/manifest.md", manifest(slug, epub, units, attrs, rights)},
      {"books/#{slug}/history.md", history_text(epub.title, nil, units_of(units), [])}
      | chapters
    ]
  end

  defp units_of(units), do: Enum.map(units, &{&1.id, &1.title})

  defp manifest(slug, epub, units, attrs, rights) do
    facts =
      [
        {"Author", epub.author},
        {"Publisher", epub.publisher},
        {"Date", epub.date},
        {"Language", epub.language},
        {"Identifier", epub.identifier},
        {"Source", blank(attrs["source"])},
        {"Rights", rights_line(rights, blank(attrs["caveat"]))},
        {"Imported", Clock.now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()}
      ]
      |> Enum.reject(&is_nil(elem(&1, 1)))
      |> Enum.map_join("\n", fn {k, v} -> "- #{k}: #{v}" end)

    contents =
      Enum.map_join(units, "\n", fn u ->
        "#{u.id}. #{u.title}: `books/#{slug}/chapters/#{u.id}.md`"
      end)

    """
    # #{epub.title}

    #{facts}

    A book in your library, imported by your witness. Read it with book_read (slug: #{slug}): with no chapter named it gives you the contents and the next chapter you have not read, and marks it read. A chapter you have not read stays out of every search until you read it with book_read; reading it by its path works, and is recorded in history.md as a peek, not a read.

    ## Chapters

    #{contents}
    """
  end

  defp rights_line(rights, nil), do: rights
  defp rights_line(rights, caveat), do: "#{rights} (#{caveat})"

  # ---- reading ----

  @doc "Her books, by title."
  def list(resident_id), do: Scope.resident(resident_id, fn -> Store.books() end)

  @doc """
  A book's contents and her place in it: each chapter with its title,
  path and state (`read`, `exposed`, `unread`), the one she is at marked.
  """
  def contents(resident_id, slug) do
    with {:ok, book} <- fetch(resident_id, slug) do
      {:ok, %{book: book, chapters: toc(book, reads(resident_id, slug))}}
    end
  end

  @doc """
  `book_read` (seshat#98): a chapter of a book, and the read stamped.
  With no unit, the next unread chapter after her place (else the first
  unread), and her place moves to it unless `advance` is false. With a
  unit, that chapter, and her place moves only when `advance` is true.
  `stamp: false` (a trial, or a later page of the same chapter) reads
  without recording anything. Answers the chapter's words with the
  contents as they stand after the read, or `done` when nothing is left
  unread and no unit was named.
  """
  def read(resident_id, slug, unit, advance, %Actor{} = actor, opts \\ []) do
    with {:ok, book} <- fetch(resident_id, slug) do
      before = reads(resident_id, slug)
      # §1: advance defaults to true when no unit is named, false when one is.
      advance = if is_nil(advance), do: is_nil(unit), else: advance == true
      unit = unit || next_unread(book, before)

      cond do
        is_nil(unit) ->
          {:ok, %{book: book, chapters: toc(book, before), done: true}}

        unit not in book.units ->
          {:error,
           Error.new(:seshat_book_no_such, :seshat_books_read_unit, path: "books/#{slug}")}

        true ->
          stamp(resident_id, book, unit, advance, before, actor, Keyword.get(opts, :stamp, true))
      end
    end
  end

  defp stamp(resident_id, book, unit, advance, before, actor, stamp?) do
    path = chapter_path(book.slug, unit)

    with {:ok, %{content: content}} <- Documents.read(resident_id, path),
         :ok <-
           if(stamp?,
             do: record(resident_id, book, unit, "read", advance, "book_read", before, actor),
             else: :ok
           ) do
      book =
        if stamp?, do: Scope.resident(resident_id, fn -> Store.book(book.slug) end), else: book

      {:ok,
       %{
         book: book,
         unit: unit,
         path: path,
         content: content,
         chapters: toc(book, reads(resident_id, book.slug)),
         done: false
       }}
    end
  end

  @doc """
  A peek (seshat#98): her `library_read` of a chapter she has not read is
  recorded as exposure, which marks nothing read, moves nothing and leaves
  the chapter dark. Any other path, or a chapter read already, records
  nothing. Answers `:exposed` or `:ok`.
  """
  def peek(resident_id, path, %Actor{} = actor) do
    with [_, slug, unit] <- Regex.run(~r{\Abooks/([^/]+)/chapters/([^/]+)\.md\z}, path),
         {:ok, book} <- fetch(resident_id, slug),
         true <- unit in book.units,
         before = reads(resident_id, slug),
         false <- read?(before, unit),
         :ok <- record(resident_id, book, unit, "exposure", false, "library_read", before, actor) do
      :exposed
    else
      _not_a_dark_chapter -> :ok
    end
  end

  # The row first; a first read lights the chapter for the index (its
  # embedding cleared, so the next run embeds it); then the history file,
  # whose write runs the index.
  defp record(resident_id, book, unit, mode, advance, via, before, actor) do
    with {:ok, _events} <-
           dispatch(%Commands.ReadBookUnit{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             slug: book.slug,
             unit: unit,
             mode: mode,
             advance: advance,
             via: via
           }) do
      _ = light(resident_id, book, unit, mode, before)
      render_history(resident_id, book.slug, actor)
    end
  end

  # A first read clears the chapter's embedding, so the next index run
  # (the history's write) embeds it.
  defp light(resident_id, book, unit, "read", before) do
    if read?(before, unit),
      do: :ok,
      else:
        Scope.resident(resident_id, fn ->
          Store.update_document(chapter_path(book.slug, unit), indexed_at: nil)
        end)
  end

  defp light(_resident_id, _book, _unit, _mode, _before), do: :ok

  defp render_history(resident_id, slug, actor) do
    book = Scope.resident(resident_id, fn -> Store.book(slug) end)
    rows = reads(resident_id, slug)
    text = history_text(book.title, book, Enum.zip(book.units, book.titles), rows)

    case Documents.write(resident_id, "books/#{slug}/history.md", text, actor, core: true) do
      {:ok, _} -> :ok
      refused -> refused
    end
  end

  defp history_text(title, book, units, rows) do
    titles = Map.new(units)
    read = rows |> Enum.filter(&(&1.mode == "read")) |> MapSet.new(& &1.unit)

    place =
      case book do
        %{current: unit} when is_binary(unit) ->
          "Your place: #{unit}. #{titles[unit]} (since #{day(book.read_at)})."

        _not_started ->
          "Not started."
      end

    lines =
      rows
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {r, i} ->
        what =
          case r do
            %{mode: "read", advanced: true} ->
              "read; your place moved here"

            %{mode: "read"} ->
              "read"

            %{mode: "exposure"} ->
              "peeked at by its path (exposure: not read, still out of search)"
          end

        "| #{i} | #{day(r.at)} | #{r.unit} | #{titles[r.unit]} | #{what} |"
      end)

    table =
      if rows == [],
        do: "Nothing read yet.",
        else: "| # | When | Chapter | Title | What |\n| --- | --- | --- | --- | --- |\n" <> lines

    """
    # Reading history: #{title}

    #{place} Read: #{MapSet.size(read)} of #{map_size(titles)} chapters.

    Rendered from the record after every reading; not written by hand.

    #{table}
    """
  end

  defp day(nil), do: "—"
  defp day(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp fetch(resident_id, slug) when is_binary(slug) do
    case Scope.resident(resident_id, fn -> Store.book(slug) end) do
      nil ->
        {:error,
         Error.new(:seshat_book_no_such, :seshat_books_fetch_absent, path: "books/#{slug}")}

      book ->
        {:ok, book}
    end
  end

  defp fetch(_resident_id, _slug),
    do: {:error, Error.new(:seshat_book_no_such, :seshat_books_fetch_slug)}

  defp reads(resident_id, slug), do: Scope.resident(resident_id, fn -> Store.book_reads(slug) end)

  defp read?(rows, unit), do: Enum.any?(rows, &(&1.unit == unit and &1.mode == "read"))
  defp exposed?(rows, unit), do: Enum.any?(rows, &(&1.unit == unit and &1.mode == "exposure"))

  defp next_unread(book, rows) do
    at = Enum.find_index(book.units, &(&1 == book.current)) || -1
    {_before, after_place} = Enum.split(book.units, at + 1)

    Enum.find(after_place, &(not read?(rows, &1))) ||
      Enum.find(book.units, &(not read?(rows, &1)))
  end

  defp toc(book, rows) do
    for {unit, title} <- Enum.zip(book.units, book.titles) do
      state =
        cond do
          read?(rows, unit) -> "read"
          exposed?(rows, unit) -> "exposed"
          true -> "unread"
        end

      %{
        unit: unit,
        title: title,
        path: chapter_path(book.slug, unit),
        state: state,
        here: unit == book.current
      }
    end
  end

  defp chapter_path(slug, unit), do: "books/#{slug}/chapters/#{unit}.md"

  defp blank(nil), do: nil

  defp blank(text),
    do: if(String.trim(to_string(text)) == "", do: nil, else: String.trim(to_string(text)))

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_books_dispatch, reason)}
    end
  end
end
