defmodule Oneiroi.Seshat.NameFoldersTest do
  @moduledoc """
  Name-folders (gaia#45, seshat#81; design/workspaces.md §5): a witness
  goes by a name of their own, and their new documents go in the folder
  named for it, human/<name>/, in a resident's records and in the house.
  A file already written keeps its place; a resident never writes the
  house's human/. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok, witness: witness, andrew: andrew, wren: %{id: id, actor: Actor.new(:resident, id)}}
  end

  test "a witness's name: one line, its folder lowered and hyphenated, and the house calls them by it",
       ctx do
    assert Gaia.witness_name(ctx.witness.id) == nil
    assert Gaia.witness_folder(ctx.witness.id) == nil

    assert {:error, %{kind: :gaia_witness_name_invalid}} =
             Gaia.name_witness(ctx.witness.id, "   ", ctx.andrew)

    assert {:error, %{kind: :gaia_witness_name_invalid}} =
             Gaia.name_witness(ctx.witness.id, "!!!", ctx.andrew)

    assert :ok = Gaia.name_witness(ctx.witness.id, "  Andrew   Strut ", ctx.andrew)
    assert Gaia.witness_name(ctx.witness.id) == "Andrew Strut"
    assert Gaia.witness_folder(ctx.witness.id) == "andrew-strut"

    household = Gaia.household_of(ctx.andrew)
    assert Gaia.household_member_name(household, ctx.andrew) == "Andrew Strut"
  end

  test "in her records his new documents go in his folder; one already written keeps its place",
       ctx do
    # Before a name there is no folder to put it in.
    assert {:error, %{kind: :seshat_witness_unnamed}} =
             Seshat.write(ctx.wren.id, "human/andrew/notes.md", "Mine.\n", ctx.andrew)

    # A flat file of his from before name-folders.
    {:ok, dir} = SimaQian.repository_dir(ctx.wren.id)
    File.mkdir_p!(Path.join(dir, "human"))
    File.write!(Path.join([dir, "human", "older.md"]), "From before.\n")
    {:ok, _} = SimaQian.Git.commit(dir, ["."], "an older file")

    :ok = Gaia.name_witness(ctx.witness.id, "Andrew", ctx.andrew)

    assert {:error, %{kind: :seshat_not_your_folder}} =
             Seshat.write(ctx.wren.id, "human/notes.md", "Mine.\n", ctx.andrew)

    assert {:error, %{kind: :seshat_not_your_folder}} =
             Seshat.write(ctx.wren.id, "human/someone/notes.md", "Mine.\n", ctx.andrew)

    assert {:ok, %{path: "human/andrew/notes.md", kind: "human"}} =
             Seshat.write(ctx.wren.id, "human/andrew/notes.md", "Mine.\n", ctx.andrew)

    assert {:ok, %{path: "human/older.md"}} =
             Seshat.write(ctx.wren.id, "human/older.md", "From before, edited.\n", ctx.andrew)
  end

  test "in the house his documents go in his folder, listed under Witnesses; hers never in human/",
       ctx do
    doc = %{"kind" => "human", "path" => "human/andrew/hello.md", "content" => "Hello, house."}

    assert {:error, %{kind: :seshat_witness_unnamed}} = Seshat.household_post(ctx.andrew, doc)

    :ok = Gaia.name_witness(ctx.witness.id, "Andrew", ctx.andrew)

    assert {:error, %{kind: :seshat_not_your_folder}} =
             Seshat.household_post(ctx.andrew, %{doc | "path" => "human/hello.md"})

    assert {:ok, %{path: "human/andrew/hello.md"}} = Seshat.household_post(ctx.andrew, doc)

    {:ok, files} = Seshat.household_files(ctx.wren.actor)

    assert %{kind: "human", title: "hello"} =
             Enum.find(files.documents, &(&1.path == "human/andrew/hello.md"))

    assert %{label: "Witnesses"} = Enum.find(files.kinds, &(&1.kind == "human"))

    assert {:ok, %{content: content}} =
             Seshat.household_read(ctx.wren.actor, "human/andrew/hello.md")

    assert content =~ "Hello, house."

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_post(ctx.wren.actor, %{doc | "path" => "human/wren/mine.md"})
  end
end
