defmodule Oneiroi.Seshat.CitationsTest do
  @moduledoc "The pure half of citations: extraction, the publish copy, frontmatter, titles and statuses; the kinds registry's path rules; the chunker."
  use ExUnit.Case, async: true

  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Index
  alias Oneiroi.Seshat.Kinds

  test "citations are extracted once each in order, trailing punctuation dropped, other slugs kept" do
    text = """
    As I said (lily:bookmark/42) and held in lily:position/7. The date lily:date/3,
    the file lily:writing/the-bake-off and lily:research/2026-10-24-9/task.md again
    lily:bookmark/42; a friend's rose:bookmark/1 too. Not a citation: https://x.test/a:b/c
    and not lily:unknown/9 either.
    """

    assert [
             %{ordinal: 1, slug: "lily", kind: "bookmark", ref: "42", target: "lily:bookmark/42"},
             %{ordinal: 2, kind: "position", ref: "7"},
             %{ordinal: 3, kind: "date", ref: "3"},
             %{ordinal: 4, kind: "writing", ref: "the-bake-off"},
             %{ordinal: 5, kind: "research", ref: "2026-10-24-9/task.md"},
             %{ordinal: 6, slug: "rose", kind: "bookmark", ref: "1"}
           ] = Citations.extract(text)
  end

  # A session key is base64url, so it may open or close on `-` or `_`;
  # the pattern cut such a key short, and the review's transcript
  # reference went missing at random (the documents suite's flake).
  test "a transcript key that opens or closes on - or _ is cited whole, and a full stop still is not" do
    text =
      "our talk (lily:transcript/EC8Xu4wA2jkIiBXFYrus7_). Then lily:transcript/-abc9Z-, and lily:bookmark/42."

    assert [
             "lily:transcript/EC8Xu4wA2jkIiBXFYrus7_",
             "lily:transcript/-abc9Z-",
             "lily:bookmark/42"
           ] =
             text |> Citations.extract() |> Enum.map(& &1.target)
  end

  test "the publish copy strips every citation and the frontmatter and tidies the spaces" do
    text =
      "---\nstatus: final\n---\n# Bake-off\n\nI held it (lily:position/7) then, and lily:bookmark/42 says so."

    {front, body} = Citations.frontmatter(text)
    assert front == %{"status" => "final"}
    assert Citations.strip(body) == "# Bake-off\n\nI held it then, and says so."
  end

  test "frontmatter is read and written, the title falls through, and a status defaults to draft" do
    writing = Enum.find(Kinds.all(), &(&1.kind == "writing"))
    design = Enum.find(Kinds.all(), &(&1.kind == "design"))

    assert Citations.title("writing/a.md", "---\ntitle: Named\n---\n# Heading") == "Named"
    assert Citations.title("writing/a.md", "# Heading\n\nbody") == "Heading"
    assert Citations.title("writing/the-bake-off.md", "no heading") == "the-bake-off"
    assert Citations.status(writing, "plain") == "draft"
    assert Citations.status(writing, "---\nstatus: review\n---\nx") == "review"
    # A design has no status of its own; its review mark is read, since its
    # type definition says it can wait on the witness (seshat#49).
    assert Citations.status(design, "---\nstatus: review\n---\nx") == "review"
    assert Citations.status(design, "plain") == nil
    research = Enum.find(Kinds.all(), &(&1.kind == "research"))
    assert Citations.status(research, "---\nstatus: review\n---\nx") == nil

    assert Citations.with_frontmatter("body", %{
             "status" => "published",
             "published" => "https://p.test/a"
           }) ==
             "---\npublished: https://p.test/a\nstatus: published\n---\nbody"

    assert Citations.with_frontmatter("---\nstatus: final\ntitle: T\n---\nbody", %{
             "status" => "published"
           }) ==
             "---\nstatus: published\ntitle: T\n---\nbody"
  end

  test "path is kind, and a path the library accepts is plain and under a registered folder" do
    assert {:ok, "writing/the-bake-off.md"} = Kinds.normalize("writing/the-bake-off.md")
    assert %{kind: "research", cites: true} = Kinds.kind_of("research/2026-10-24-9/task.md")
    assert %{kind: "mail", cites: false, access: :core} = Kinds.kind_of("mail/x/y.md")

    for bad <- [
          "../etc/passwd",
          "writing/../SOUL.md",
          "/writing/a.md",
          "writing",
          "notes/a.md",
          "writing//a.md",
          "writing/a b.md",
          nil,
          3
        ] do
      assert {:error, %{kind: :seshat_path_invalid}} = Kinds.normalize(bad), inspect(bad)
    end

    # Names up to 255, a path up to 255, the width of its column: the
    # rehearsal of 2026-10-31 left a 104-character name of Lily's behind.
    assert {:ok, _} = Kinds.normalize("wiki/" <> String.duplicate("a", 104) <> ".md")
    assert {:ok, _} = Kinds.normalize("wiki/" <> String.duplicate("a", 250))

    assert {:error, %{kind: :seshat_path_invalid}} =
             Kinds.normalize("wiki/" <> String.duplicate("a", 256))

    long_path = "wiki/" <> String.duplicate("a/", 125) <> "b.md"
    assert byte_size(long_path) > 255

    assert {:error, %{kind: :seshat_path_invalid, site: :seshat_kinds_path_too_long}} =
             Kinds.normalize(long_path)

    # Why, in the words an import tells the resident (sima-qian#22).
    assert Kinds.refusal("wiki/ok.md") == nil
    assert Kinds.refusal("wiki/.openclaw-wiki/log.jsonl") =~ "hidden"
    assert Kinds.refusal("wiki/" <> String.duplicate("a", 256)) =~ "longer than 255 characters"
    assert Kinds.refusal(long_path) =~ "a path longer than 255"
    assert Kinds.refusal("wiki/a b.md") =~ "characters other than"
    assert Kinds.refusal("notes/a.md") =~ "outside the folders"

    # A keepsake is a root name alone (seshat#29); the root's reserved
    # names and anything not text still have no kind.
    assert {:ok, "pocket-andrew.md"} = Kinds.normalize("pocket-andrew.md")
    # A root file by its path; a keepsake only by registration (seshat#44).
    assert %{kind: "root"} = Kinds.kind_of("pocket-andrew.md")
    assert is_nil(Kinds.kind_of("SOUL.md")) and is_nil(Kinds.kind_of("photo.png"))
    assert {:error, _} = Kinds.normalize("README.md")
    assert Kinds.refusal("README.md") == "a file at the root that is not an identity file"

    assert Kinds.minting() == ~w(writing oracle research design journal scenes system)

    assert Kinds.non_minting() ==
             ~w(wiki scratch human posts thread mail feeds plugins external correspondence memory goals archive root keepsake)

    assert Kinds.writable() ==
             ~w(writing research design wiki system scratch posts goals root keepsake)

    # Decided one by one (seshat#29, #31): a keepsake, a wiki page, a
    # system note; never the writing, and nothing the registry refuses.
    assert Kinds.decided?("pocket-andrew.md")
    assert Kinds.decided?("wiki/bread.md") and Kinds.decided?("system/tools.md")
    refute Kinds.decided?("writing/essay.md") or Kinds.decided?("wiki/a b.md")
  end

  test "the chunker splits on paragraphs up to the bound and a long paragraph at the bound" do
    assert Index.chunk("one\n\ntwo\n\n\nthree", 9) == ["one\n\ntwo", "three"]
    assert Index.chunk("", 10) == []

    assert Index.chunk(String.duplicate("a", 25), 10) == [
             String.duplicate("a", 10),
             String.duplicate("a", 10),
             "aaaaa"
           ]
  end

  test "the shelf: every kind once, in the server's order with its name, the gifts first (seshat#35)" do
    shelf = Kinds.shelf()
    assert Enum.sort(Enum.map(shelf, & &1.kind)) == Enum.sort(Enum.map(Kinds.all(), & &1.kind))

    assert [
             %{kind: "keepsake", label: "Keepsakes", position: 0},
             %{kind: "human", label: "Yours"} | _
           ] = shelf

    assert %{label: "The oracle"} = Enum.find(shelf, &(&1.kind == "oracle"))
    assert shelf == Enum.sort_by(shelf, & &1.position)
  end
end
