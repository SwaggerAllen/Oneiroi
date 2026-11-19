defmodule Oneiroi.Seshat.BooksTest do
  @moduledoc """
  The reading library (seshat#98), through its exports and the brain's
  tools, as Lily's acceptance test reads (design/reading-library-build.md
  §2): an unread chapter is dark to search; it is readable by its path and
  in the repository; that read is recorded as a peek, advancing nothing
  and leaving it dark; book_read marks it read; then search finds it.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Tools
  alias Oneiroi.EpubFixture
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    Fake.clear()
    on_exit(fn -> File.rm_rf!(dir) end)
    her = Actor.new(:resident, resident.id)
    turn = %{resident_id: resident.id, session_key: "s", turn_ref: "t", resident: her}
    {:ok, id: resident.id, witness: actor, her: her, turn: turn, dir: dir}
  end

  @chapters [
    {"I. The Gate", ["The heron stood at the weir all morning."]},
    {"II. The Field", ["Marrowfield lay under frost, and nobody crossed it."]},
    {"III. The End", ["The lighthouse keeper was the thief all along."]}
  ]

  defp import!(ctx, opts \\ []) do
    {:ok, book} =
      Seshat.book_import(
        ctx.id,
        EpubFixture.build(@chapters, opts),
        %{"rights" => "public-domain", "source" => "field.epub"},
        ctx.witness
      )

    book
  end

  defp run(ctx, name, args), do: Tools.run(name, Jason.encode!(args), ctx.turn)

  defp found?(ctx, query, path) do
    {:ok, hits} = Seshat.search(ctx.id, query, ctx.her)
    Enum.any?(hits, &(&1.path == path))
  end

  test "an import is one folder: the manifest, each chapter a document, an empty history; the same edition again is refused",
       ctx do
    book = import!(ctx)
    assert book.slug == "the-long-field"
    assert book.units == ["001", "002", "003"]
    assert book.titles == ["I. The Gate", "II. The Field", "III. The End"]

    manifest = File.read!(Path.join(ctx.dir, "books/the-long-field/manifest.md"))
    assert manifest =~ "# The Long Field"
    assert manifest =~ "- Author: Ada Wren"
    assert manifest =~ "- Rights: public-domain"
    assert manifest =~ "- Source: field.epub"
    assert manifest =~ "002. II. The Field: `books/the-long-field/chapters/002.md`"

    assert File.read!(Path.join(ctx.dir, "books/the-long-field/chapters/003.md")) =~
             "The lighthouse keeper was the thief all along."

    assert File.read!(Path.join(ctx.dir, "books/the-long-field/history.md")) =~
             "Nothing read yet."

    assert {:error, %{kind: :seshat_book_imported, details: [path: "books/the-long-field"]}} =
             Seshat.book_import(
               ctx.id,
               EpubFixture.build(@chapters),
               %{"rights" => "public-domain"},
               ctx.witness
             )

    # Another edition of the same title takes the next folder.
    assert %{slug: "the-long-field-2"} = import!(ctx, identifier: "urn:other")

    # A rights note is required, and only her witness imports.
    assert {:error, %{kind: :seshat_book_invalid}} =
             Seshat.book_import(ctx.id, EpubFixture.build(@chapters), %{}, ctx.witness)

    assert {:error, %{kind: :seshat_book_invalid}} =
             Seshat.book_import(
               ctx.id,
               EpubFixture.build(@chapters),
               %{"rights" => "public-domain"},
               ctx.her
             )
  end

  test "the unread floor: dark to search, readable by its path as a peek that marks nothing, lit by book_read",
       ctx do
    import!(ctx)
    ending = "books/the-long-field/chapters/003.md"
    words = "The lighthouse keeper was the thief all along."

    # Unread: no search returns it.
    refute found?(ctx, words, ending)

    # Retrievable by its path, and in the repository (the export).
    assert File.exists?(Path.join(ctx.dir, ending))
    peek = run(ctx, "library_read", %{path: ending})
    assert peek =~ words
    assert peek =~ "recorded in the book's history as a peek"

    # The peek is exposure: nothing read, her place unmoved, still dark.
    {:ok, %{book: book, chapters: chapters}} = Seshat.book_contents(ctx.id, "the-long-field")
    assert book.current == nil
    assert Enum.map(chapters, & &1.state) == ["unread", "unread", "exposed"]
    refute found?(ctx, words, ending)

    assert File.read!(Path.join(ctx.dir, "books/the-long-field/history.md")) =~
             "peeked at by its path"

    # book_read with no unit: the next unread, marked read, her place there.
    first = run(ctx, "book_read", %{slug: "the-long-field"})
    assert first =~ "Chapter 001, I. The Gate"
    assert first =~ "Marked read; your place is here."
    assert first =~ "The heron stood at the weir"

    # Out of order, without advancing: that chapter alone, her place kept.
    third = run(ctx, "book_read", %{slug: "the-long-field", unit: "003"})
    assert third =~ "Marked read; your place stays at 001."
    {:ok, %{book: book, chapters: chapters}} = Seshat.book_contents(ctx.id, "the-long-field")
    assert book.current == "001"
    assert Enum.map(chapters, & &1.state) == ["read", "unread", "read"]

    # Read, it is ordinary text: search finds it.
    assert found?(ctx, words, ending)
    refute found?(ctx, "Marrowfield lay under frost", "books/the-long-field/chapters/002.md")

    # The next unread is after her place; a reread moves nothing.
    assert run(ctx, "book_read", %{slug: "the-long-field"}) =~ "Chapter 002, II. The Field"

    assert run(ctx, "book_read", %{slug: "the-long-field", unit: "001"}) =~
             "your place stays at 002"

    assert run(ctx, "book_read", %{slug: "the-long-field"}) =~ "You have read every chapter."

    history = File.read!(Path.join(ctx.dir, "books/the-long-field/history.md"))
    assert history =~ "Your place: 002. II. The Field"
    assert history =~ "Read: 3 of 3 chapters."
  end

  test "her books listed; a book and her reading of it are never published or copied to the house",
       ctx do
    import!(ctx)

    assert run(ctx, "book_read", %{}) =~
             "the-long-field: The Long Field, by Ada Wren; 3 chapters, not started"

    assert {:error, %{kind: :seshat_book_private}} =
             Seshat.publish(
               ctx.id,
               "books/the-long-field/chapters/001.md",
               nil,
               "share it",
               ctx.her
             )
  end
end
