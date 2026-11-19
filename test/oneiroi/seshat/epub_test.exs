defmodule Oneiroi.Seshat.EpubTest do
  @moduledoc "An EPUB read into its facts and its chapters as markdown (seshat#98)."
  use ExUnit.Case, async: true

  alias Oneiroi.EpubFixture
  alias Oneiroi.Seshat.Epub

  test "the package's facts, and each page with words a chapter, in the spine's order" do
    bytes =
      EpubFixture.build([
        {"I. The Gate", ["It was <em>late</em> &amp; cold.", "Nobody came."]},
        {"II. The Field", ["The field was <strong>long</strong>&#8212;longer than it looked."]}
      ])

    assert {:ok, book} = Epub.parse(bytes)
    assert book.title == "The Long Field"
    assert book.author == "Ada Wren"
    assert book.identifier == "urn:uuid:4e1f-field"
    assert book.publisher == "Small Press"
    # The cover has no words and is no chapter.
    assert [first, second] = book.chapters
    assert first.title == "I. The Gate"
    assert first.text == "# I. The Gate\n\nIt was *late* & cold.\n\nNobody came."
    assert second.text =~ "The field was **long**—longer than it looked."
  end

  test "a package at the root, and markup the reader keeps: quotations, lists, breaks" do
    bytes =
      EpubFixture.build(
        [{"Notes", ["One<br/>two", "<span>a</span> <i>b</i>"]}],
        dir: nil
      )

    assert {:ok, %{chapters: [%{text: text}]}} = Epub.parse(bytes)
    assert text =~ "One\ntwo"
    assert text =~ "a *b*"

    assert Epub.markdown(
             "<body><blockquote><p>Said.</p></blockquote><ul><li>x</li><li>y</li></ul></body>"
           ) ==
             "> Said.\n\n- x\n- y"
  end

  test "what is not an EPUB is refused with why" do
    assert {:error,
            %{
              kind: :seshat_book_invalid,
              details: [reason: "the file is not an EPUB (it is not a readable zip)"]
            }} =
             Epub.parse("not a zip")

    {:ok, {_, empty}} = :zip.create(~c"x.zip", [{~c"a.txt", "a"}], [:memory])

    assert {:error, %{details: [reason: "the file is not an EPUB (no META-INF/container.xml)"]}} =
             Epub.parse(empty)

    assert {:error, %{details: [reason: "the EPUB has no chapter with words in it"]}} =
             Epub.parse(EpubFixture.build([{"", [""]}]))
  end
end
