defmodule Oneiroi.AgathosDaimon.FilesTest do
  @moduledoc "The identity files through the exports: seeds with origins, the rendered AGENTS.md, proposals after first contact, the row's versions."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)

    {:ok,
     resident: resident,
     witness: Actor.new(:witness, witness.id),
     brain: Actor.new(:resident, resident.id, "fake/model")}
  end

  test "seeds carry their origin and version, and AGENTS.md is rendered, never written", ctx do
    id = ctx.resident.id
    assert [] = AgathosDaimon.files(id)

    assert :ok =
             AgathosDaimon.write_file(
               id,
               "SOUL.md",
               "# Soul",
               %{origin: "drafted", model: "fake/model", prompt: "be kind"},
               ctx.witness
             )

    assert :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul, again", %{}, ctx.witness)

    assert [
             %{
               name: "SOUL.md",
               content: "# Soul, again",
               origin: "drafted",
               model: "fake/model",
               version: 2
             }
           ] =
             AgathosDaimon.files(id)

    assert {:ok, %{name: "AGENTS.md", origin: "build", content: content}} =
             AgathosDaimon.file(id, "AGENTS.md")

    assert content =~ "Lily" and content =~ ctx.resident.slug <> ":bookmark/42"

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_file_unknown}} =
             AgathosDaimon.write_file(id, "AGENTS.md", "x", %{}, ctx.witness)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_no_such_file}} =
             AgathosDaimon.file(id, "USER.md")

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_write_instead}} =
             AgathosDaimon.propose_edit(id, "SOUL.md", "x", "n", ctx.witness)
  end

  test "after first contact the witness proposes and the resident decides, with notes", ctx do
    id = ctx.resident.id
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul", %{}, ctx.witness)
    :ok = AgathosDaimon.first_contact(id, "s1", "t1", ctx.brain)
    :ok = AgathosDaimon.first_contact(id, "s1", "t2", ctx.brain)

    assert {:ok, %{first_contact_at: %DateTime{} = at, formation_until: until}} =
             AgathosDaimon.fetch(id)

    assert DateTime.diff(until, at, :day) == 30

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_propose_instead}} =
             AgathosDaimon.write_file(id, "SOUL.md", "# Bolder", %{}, ctx.witness)

    assert {:ok, ref} =
             AgathosDaimon.propose_edit(id, "SOUL.md", "# Bolder", "you have grown", ctx.witness)

    assert [%{ref: ^ref, file: "SOUL.md", note: "you have grown", state: "open"}] =
             AgathosDaimon.edit_proposals(id)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_the_resident}} =
             AgathosDaimon.accept_edit(id, ref, "yes", ctx.witness)

    assert :ok = AgathosDaimon.accept_edit(id, ref, "yes, I have", ctx.brain)
    assert [] = AgathosDaimon.edit_proposals(id)

    assert {:ok, %{content: "# Bolder", version: 2, written_by_kind: "resident"}} =
             AgathosDaimon.file(id, "SOUL.md")

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_no_such_proposal}} =
             AgathosDaimon.accept_edit(id, ref, "again", ctx.brain)

    assert {:ok, ref2} = AgathosDaimon.propose_edit(id, "SOUL.md", "# Meeker", "hm", ctx.witness)
    assert :ok = AgathosDaimon.decline_edit(id, ref2, "that is not me", ctx.brain)
    assert {:ok, %{content: "# Bolder"}} = AgathosDaimon.file(id, "SOUL.md")

    # The resident's own edit applies at any time, with no proposal.
    assert :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Mine", %{}, ctx.brain)
    assert {:ok, %{content: "# Mine", version: 3}} = AgathosDaimon.file(id, "SOUL.md")
  end
end
