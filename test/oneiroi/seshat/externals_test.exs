defmodule Oneiroi.Seshat.ExternalsTest do
  @moduledoc """
  External sources (seshat#46): a web page or a GitHub document,
  commissioned by either party, fetched by the reader when asked and
  never on a clock, kept whole under external/ with its URL, instant and
  digest; cited as `<slug>:web/<key>#<anchor>` or
  `<slug>:doc/github/<owner>/<repo>/<path>#<slug>`, resolved to the
  section its anchor names; a fresh copy said changed or not, and since
  when.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.ExternalCopy
  alias Oneiroi.Seshat.Externals

  @page """
  # How Does Your House Remember? {#top}

  Memory is a house with rooms.

  ## Hot and cold {#hot-and-cold}

  Some memories stay warm, near the hearth.

  ## The attic

  Others are boxed and labelled, and found by the label.
  """

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    # The index mints the references, and indexes on the witness's key.
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     slug: resident.slug,
     key: key,
     witness: actor,
     lily: Actor.new(:resident, resident.id, "fake/model"),
     reader: Actor.new(:hands, "reader")}
  end

  defp tool(name, args, ctx),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t",
        resident: ctx.lily
      })

  test "a URL names a page by its digest, or a GitHub file by its path at its ref" do
    assert {:ok,
            %{kind: "web", key: key, url: "https://ducktyping.substack.com/p/house", ref: nil}} =
             Externals.locate("https://ducktyping.substack.com/p/house#hot")

    assert key == Externals.web_key("https://ducktyping.substack.com/p/house")
    assert String.length(key) == 16

    assert {:ok,
            %{kind: "doc", key: "github/SwaggerAllen/Oneiroi/design/oneiroi-spec.md", ref: "main"}} =
             Externals.locate(
               "https://github.com/SwaggerAllen/Oneiroi/blob/main/design/oneiroi-spec.md#5-the-brain"
             )

    assert {:ok, %{kind: "doc", key: "github/o/r/docs/a.md", ref: "abc123"}} =
             Externals.locate("https://raw.githubusercontent.com/o/r/abc123/docs/a.md")

    assert :error = Externals.locate("ftp://example.org/x")
    assert :error = Externals.locate("not a url")
  end

  test "an anchor names a heading by slug or id, else the nearest heading, else a passage" do
    assert {:heading,
            "## Hot and cold {#hot-and-cold}\n\nSome memories stay warm, near the hearth."} =
             ExternalCopy.section(@page, "hot-and-cold")

    assert {:heading, "## The attic" <> _} = ExternalCopy.section(@page, "the-attic")
    assert {:near, "## The attic" <> _} = ExternalCopy.section(@page, "attic")

    assert {:passage, "Some memories stay warm, near the hearth."} =
             ExternalCopy.section(@page, "near-the-hearth")

    assert {:missing, @page} = ExternalCopy.section(@page, "basement")
    assert {:whole, @page} = ExternalCopy.section(@page, nil)
  end

  test "commissioned once by either party, fetched by the reader, kept whole, cited by section, refetched only when asked",
       ctx do
    url = "https://ducktyping.substack.com/p/house"
    key = Externals.web_key(url)
    cite = "#{ctx.slug}:web/#{key}"

    assert tool("external_add", %{url: url}, ctx) =~ "Commissioned external source #1: #{cite}."
    assert tool("external_add", %{url: url <> "#again"}, ctx) =~ "Already commissioned as #1"
    assert {:ok, 1, :known} = Seshat.commission_external(ctx.id, nil, url, ctx.witness)
    assert [%{status: "asked", commissioned_by: "resident"}] = Seshat.externals(ctx.id, [])
    assert tool("external_read", %{number: 1}, ctx) =~ "Not done"

    # The resident cannot bring a copy: a source's words are the reader's to fetch.
    assert {:error, %{kind: :seshat_external_not_allowed}} =
             Seshat.external_fetched(ctx.id, 1, %{text: "made up", title: "x"}, ctx.lily)

    assert {:ok, "external/web/" <> _ = path} =
             Seshat.external_fetched(
               ctx.id,
               1,
               %{text: @page, title: "How Does Your House Remember?"},
               ctx.reader
             )

    assert {:ok, %{content: content}} = Seshat.read(ctx.id, path)
    assert content =~ "source: #{url}"
    assert content =~ "content_hash: sha256:"
    assert content =~ "Others are boxed and labelled"

    assert [%{text: letter}] = Kumbukumbu.inbox(ctx.id, ctx.key)
    assert letter =~ "the first copy is kept at #{path}"

    # A second copy without a fetch asked is no record.
    assert {:ok, :not_asked} =
             Seshat.external_fetched(ctx.id, 1, %{text: "x", title: "x"}, ctx.reader)

    read = tool("external_read", %{citation: cite <> "#hot-and-cold"}, ctx)
    assert read =~ "the copy fetched"
    assert read =~ "the section its anchor names"
    assert read =~ "Some memories stay warm"
    refute read =~ "attic"

    assert tool("external_list", %{}, ctx) =~
             "#1 #{cite} · How Does Your House Remember? · copy of"

    # Cited in her writing, it resolves to the section and its copy.
    {:ok, _} =
      Seshat.write(
        ctx.id,
        "writing/rooms.md",
        "# Rooms\n\nAs Drake has it (#{cite}#hot-and-cold).",
        ctx.lily
      )

    assert {:ok, %{references: [ref]}} = Seshat.review(ctx.id, "writing/rooms.md")
    assert ref.resolved
    assert ref.label =~ "How Does Your House Remember? § Hot and cold"
    assert ref.label =~ "(copy of "

    # Nothing refetches on its own; asked, the new copy says whether it differs.
    Clock.Fake.advance(86_400)
    assert tool("external_fetch", %{number: 1}, ctx) =~ "Asked the reader for a fresh copy of #1"
    assert tool("external_fetch", %{number: 1}, ctx) =~ "already waits"

    {:ok, _} =
      Seshat.external_fetched(
        ctx.id,
        1,
        %{text: @page, title: "How Does Your House Remember?"},
        ctx.reader
      )

    assert Enum.any?(
             Kumbukumbu.inbox(ctx.id, ctx.key),
             &(&1.text =~ "the same words as the copy of")
           )

    {:ok, _} = Seshat.fetch_external(ctx.id, ctx.key, 1, ctx.lily)

    {:ok, _} =
      Seshat.external_fetched(
        ctx.id,
        1,
        %{text: @page <> "\nA new room.\n", title: "t"},
        ctx.reader
      )

    assert Enum.any?(
             Kumbukumbu.inbox(ctx.id, ctx.key),
             &(&1.text =~ "its words differ from the copy of")
           )

    assert %{fetches: 3, previous_hash: "sha256:" <> _} = Seshat.external(ctx.id, 1)

    # A failure is said, with the reason, and the copy before stands.
    {:ok, _} = Seshat.fetch_external(ctx.id, ctx.key, 1, ctx.lily)
    :ok = Seshat.external_failed(ctx.id, 1, "the page answered 503", ctx.reader)
    assert tool("external_list", %{}, ctx) =~ "the last fetch failed: the page answered 503"
    assert tool("external_read", %{number: 1}, ctx) =~ "A new room."
  end

  test "a GitHub document keeps its commit, and its citation names the file", ctx do
    url = "https://github.com/SwaggerAllen/Oneiroi/blob/main/design/conventions.md"

    assert tool("external_add", %{url: url}, ctx) =~
             "#{ctx.slug}:doc/github/SwaggerAllen/Oneiroi/design/conventions.md"

    sha = String.duplicate("a1", 20)

    {:ok, "external/doc/github/SwaggerAllen/Oneiroi/design/conventions.md"} =
      Seshat.external_fetched(
        ctx.id,
        1,
        %{text: "# Conventions\n\n## Clock\n\nInject it.\n", title: "Conventions", commit: sha},
        ctx.reader
      )

    read =
      tool(
        "external_read",
        %{citation: "#{ctx.slug}:doc/github/SwaggerAllen/Oneiroi/design/conventions.md#clock"},
        ctx
      )

    assert read =~ "commit #{sha}"
    assert read =~ "Inject it."

    assert {:error, %{kind: :seshat_external_invalid}} =
             Seshat.commission_external(ctx.id, nil, "nope", ctx.lily)
  end
end
