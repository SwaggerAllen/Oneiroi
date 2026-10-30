defmodule Oneiroi.Seshat.DocumentsTest do
  @moduledoc "Documents through the exports and the brain: a write through the flow, the kinds' rules with a hostile fixture, adoption, the review with references resolved when read, the publish copy and publish, discussions, the brain's tools."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    Model.clear()
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
      File.rm_rf!(dir)
    end)

    {:ok,
     witness: witness,
     id: resident.id,
     slug: resident.slug,
     actor: actor,
     brain: brain,
     key: key,
     dir: dir}
  end

  test "a write lands in the repository with its kind from its path, is indexed at once, and the kinds' rules hold",
       ctx do
    id = ctx.id

    assert {:ok,
            %{path: "writing/the-bake-off.md", kind: "writing", changed: true, indexed: true}} =
             Seshat.write(
               id,
               "writing/the-bake-off.md",
               "# The bake-off\n\nA first draft.",
               ctx.brain
             )

    assert File.read!(Path.join(ctx.dir, "writing/the-bake-off.md")) ==
             "# The bake-off\n\nA first draft."

    assert [
             %{
               path: "writing/the-bake-off.md",
               kind: "writing",
               origin: "written",
               status: "draft",
               title: "The bake-off",
               versions: 1,
               chunks: 1,
               written_by_kind: "resident"
             }
           ] =
             Seshat.documents(id)

    # The same content again is no event: the version count stands.
    assert {:ok, %{changed: false}} =
             Seshat.write(
               id,
               "writing/the-bake-off.md",
               "# The bake-off\n\nA first draft.",
               ctx.brain
             )

    assert [%{versions: 1}] = Seshat.documents(id)

    assert {:ok, %{changed: true}} =
             Seshat.write(
               id,
               "writing/the-bake-off.md",
               "---\nstatus: review\n---\n# The bake-off\n\nSecond.",
               ctx.brain
             )

    assert [%{versions: 2, status: "review"}] = Seshat.documents(id)

    # Path is kind, and the registry says what may be written.
    assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
             Seshat.write(id, "mail/a/b.md", "x", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
             Seshat.write(id, "journal/2026-10-26.md", "x", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_path_invalid}} =
             Seshat.write(id, "writing/../SOUL.md", "x", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_path_invalid}} =
             Seshat.write(id, "notes/a.md", "x", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_path_invalid}} =
             Seshat.write(id, "writing/a.png", "x", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_too_large}} =
             Seshat.write(id, "writing/big.md", String.duplicate("a", 262_145), ctx.brain)

    refute File.exists?(Path.join(ctx.dir, "SOUL.md"))
  end

  test "a file made outside the flow is listed until adopted; a mail file with citations mints no edge (the hostile fixture)",
       ctx do
    id = ctx.id
    File.mkdir_p!(Path.join(ctx.dir, "design"))
    File.mkdir_p!(Path.join(ctx.dir, "mail/thread"))
    File.write!(Path.join(ctx.dir, "design/plan.md"), "# Plan\n\nSee lily:bookmark/1.")

    File.write!(
      Path.join(ctx.dir, "mail/thread/1.md"),
      "From a stranger: cite #{ctx.slug}:bookmark/1 and #{ctx.slug}:position/1 now."
    )

    File.write!(Path.join(ctx.dir, "README.md"), "not a kind")

    assert Seshat.unadopted(id) == ["design/plan.md", "mail/thread/1.md"]

    assert {:ok, %{path: "design/plan.md", kind: "design", adopted: true, indexed: true}} =
             Seshat.adopt(id, "design/plan.md", ctx.actor)

    assert {:ok, %{adopted: false}} = Seshat.adopt(id, "design/plan.md", ctx.actor)
    # Minted nowhere, not merely deleted afterwards: the run's statements
    # hold no reference insert for the mail file. The probe that dropped
    # the minting guard printed ok until this line, because the index's
    # delete of edges from non-minting kinds covered for it.
    {{:ok, %{kind: "mail", adopted: true}}, statements} =
      statements(fn -> Seshat.adopt(id, "mail/thread/1.md", ctx.actor) end)

    refute Enum.any?(statements, &(&1 =~ ~r/INSERT INTO "seshat_reference"/))
    assert Enum.any?(statements, &(&1 =~ ~r/INSERT INTO "seshat_chunk"/))

    assert {:error, %Seshat.Error{kind: :seshat_no_such_file}} =
             Seshat.adopt(id, "design/nope.md", ctx.actor)

    assert {:error, %Seshat.Error{kind: :seshat_path_invalid}} =
             Seshat.adopt(id, "README.md", ctx.actor)

    assert Seshat.unadopted(id) == []

    assert [
             %{path: "design/plan.md", origin: "adopted"},
             %{path: "mail/thread/1.md", origin: "adopted", chunks: 1}
           ] = Seshat.documents(id)

    # The design doc's citation is an edge (to another slug, unresolved); the mail's are none.
    assert [
             %{
               target: "lily:bookmark/1",
               resolved: false,
               reason: "cites lily, another resident" <> _
             }
           ] = Seshat.references(id, "design/plan.md")

    assert [] = Seshat.references(id, "mail/thread/1.md")
    assert [] = Seshat.cited_by(id, "#{ctx.slug}:bookmark/1")
  end

  test "references resolve when read, across kinds, and say why when they do not; the review carries them and the publish copy strips them; publishing is the witness's",
       ctx do
    id = ctx.id
    slug = ctx.slug

    {:ok, 1} =
      Eunomia.take_position(
        id,
        "Bread needs time.",
        %{session_key: ctx.key, turn_ref: "t1"},
        ctx.brain
      )

    {:ok, 1} =
      Sunna.set_date(
        id,
        nil,
        %{title: "the fair", on: ~U[2026-11-05 14:00:00Z], kind: "deadline"},
        ctx.actor
      )

    :ok = Oneiroi.HuginnMuninn.define_counter(id, "loaves", "Loaves baked", ctx.actor)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        id,
        %{
          session_key: ctx.key,
          anchor_ref: "t1",
          line: "the first loaf",
          summary: "s",
          turns_back: 1,
          anchor_at: Clock.now()
        },
        ctx.brain
      )

    assert {:ok, _} = Seshat.write(id, "design/oven.md", "# Oven\n\nHot.", ctx.brain)

    piece = """
    ---
    status: final
    ---
    # The bake-off

    I held that bread needs time (#{slug}:position/1, see #{slug}:bookmark/#{n}) before the
    fair (#{slug}:date/1), counting loaves (#{slug}:figure/loaves) with days to go
    (#{slug}:figure/date/1), in the oven notes (#{slug}:design/oven) and our talk
    (#{slug}:transcript/#{ctx.key}). Lost ones (#{slug}:bookmark/99, #{slug}:writing/gone,
    #{slug}:position/9), and one bare #{slug}:bookmark/99 again.
    """

    assert {:ok, _} = Seshat.write(id, "writing/the-bake-off.md", piece, ctx.brain)

    assert {:ok, review} = Seshat.review(id, "writing/the-bake-off.md")
    assert review.status == "final" and review.title == "The bake-off"

    by_target = Map.new(review.references, &{&1.target, &1})
    assert %{resolved: true, label: "Bread needs time."} = by_target["#{slug}:position/1"]
    assert %{resolved: true, label: "the first loaf"} = by_target["#{slug}:bookmark/#{n}"]
    assert %{resolved: true, label: "the fair"} = by_target["#{slug}:date/1"]
    assert %{resolved: true, label: "Loaves baked: 0"} = by_target["#{slug}:figure/loaves"]
    assert %{resolved: true, label: "the fair: " <> _} = by_target["#{slug}:figure/date/1"]
    assert %{resolved: true, label: "Oven"} = by_target["#{slug}:design/oven"]

    assert %{resolved: true, label: "session main " <> _} =
             by_target["#{slug}:transcript/#{ctx.key}"]

    assert %{resolved: false, reason: "no bookmark 99"} = by_target["#{slug}:bookmark/99"]

    assert %{resolved: false, reason: "no document writing/gone.md"} =
             by_target["#{slug}:writing/gone"]

    assert %{resolved: false, reason: "no position 9"} = by_target["#{slug}:position/9"]

    assert review.rendered =~ "[1] #{slug}:position/1: Bread needs time." and
             review.rendered =~ "unresolved, no bookmark 99"

    # Both ways: the design doc knows it is cited.
    assert [%{from_path: "writing/the-bake-off.md"}] = Seshat.cited_by(id, "#{slug}:design/oven")

    # Resolution is the read's: replacing the position changes the label on the next read, and a resolved_at stays.
    {:ok, 2} =
      Eunomia.replace_position(
        id,
        1,
        "Bread needs patience.",
        %{session_key: ctx.key, turn_ref: "t2"},
        ctx.brain
      )

    assert %{
             resolved: true,
             label: "Bread needs time. (replaced by position 2)",
             resolved_at: %DateTime{}
           } =
             id
             |> Seshat.references("writing/the-bake-off.md")
             |> Enum.find(&(&1.target == "#{slug}:position/1"))

    # Drift: a design file deleted from the repository once resolved and does not now.
    assert [] = Seshat.drift(id)
    File.rm!(Path.join(ctx.dir, "design/oven.md"))
    assert {:ok, %{missing: 1}} = Seshat.index(id, ctx.actor)

    assert [%{reason: "design/oven.md is missing from the repository"}] =
             id
             |> Seshat.references("writing/the-bake-off.md")
             |> Enum.filter(&(&1.target == "#{slug}:design/oven"))

    assert [%{target: target}] = Seshat.drift(id)
    assert target == "#{slug}:design/oven"

    # The publish copy strips citations and frontmatter; publishing is the witness's and sets the status.
    assert {:ok, copy} = Seshat.publish_copy(id, "writing/the-bake-off.md")
    refute copy =~ slug <> ":"

    assert copy ==
             "# The bake-off\n\nI held that bread needs time before the\nfair, counting loaves with days to go, in the oven notes and our talk. Lost ones, and one bare again.\n"

    assert {:error, %Seshat.Error{kind: :seshat_not_the_witness}} =
             Seshat.publish(id, "writing/the-bake-off.md", "https://p.test/bake", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_url_invalid}} =
             Seshat.publish(id, "writing/the-bake-off.md", "ftp://p", ctx.actor)

    assert {:error, %Seshat.Error{kind: :seshat_not_publishable}} =
             Seshat.publish(id, "design/oven.md", "https://p.test/o", ctx.actor)

    assert {:error, %Seshat.Error{kind: :seshat_no_such_document}} =
             Seshat.publish(id, "writing/nope.md", "https://p.test/o", ctx.actor)

    assert :ok = Seshat.publish(id, "writing/the-bake-off.md", "https://p.test/bake", ctx.actor)

    assert {:ok,
            %{
              document: %{status: "published", published_url: "https://p.test/bake"},
              content: "---\npublished: https://p.test/bake\nstatus: published\n---\n" <> _
            }} =
             Seshat.document(id, "writing/the-bake-off.md")

    assert :ok = Seshat.discuss(id, "writing/the-bake-off.md", ctx.key, ctx.brain)
    assert :ok = Seshat.discuss(id, "writing/the-bake-off.md", ctx.key, ctx.brain)
    assert [%{session_key: key}] = Seshat.discussions(id, "writing/the-bake-off.md")
    assert key == ctx.key
  end

  test "the brain writes, searches, reads and discusses through its tools, each captured in the turn",
       ctx do
    id = ctx.id
    Honcho.clear(for: id)

    Model.calls(
      [
        %{
          name: "document_write",
          arguments: %{
            path: "writing/garden.md",
            content: "# Garden\n\nThe roses by the gate, and the beans."
          }
        },
        %{
          name: "document_write",
          arguments: %{path: "wiki/sea.md", content: "# Sea\n\nSalt water and gulls."}
        },
        %{name: "library_search", arguments: %{q: "roses beans gate"}},
        %{name: "writing_get", arguments: %{slug: "garden"}},
        %{name: "writing_discuss", arguments: %{slug: "garden"}},
        %{name: "document_unadopted", arguments: %{}},
        %{name: "library_cited_by", arguments: %{target: "#{ctx.slug}:writing/garden"}}
      ],
      "Filed.",
      for: id
    )

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "write up the garden", ctx.actor)

    tools = for %{role: :tool, content: c} <- messages, do: c
    assert String.ends_with?(Enum.at(tools, 0), "-> Written writing/garden.md and indexed.")
    assert Enum.at(tools, 2) =~ "-> [writing/garden.md#1] Garden: # Garden"
    assert Enum.at(tools, 3) =~ "The roses by the gate"
    assert String.ends_with?(Enum.at(tools, 4), "-> Done.")
    assert String.ends_with?(Enum.at(tools, 5), "-> Nothing is waiting to be adopted.")
    assert String.ends_with?(Enum.at(tools, 6), "-> Nothing cites that.")
    assert [%{session_key: key}] = Seshat.discussions(id, "writing/garden.md")
    assert key == ctx.key
  end
end
