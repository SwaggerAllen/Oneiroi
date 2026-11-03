defmodule Oneiroi.Seshat.ScratchHumanTest do
  @moduledoc "Two kinds (seshat #33): scratch/ holds temporary workshop state the resident writes and removes; human/ holds the witness's own documents, which the resident reads and never writes. Only these two are removable, and the removal is recorded with its actor."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     dir: dir,
     witness: Actor.new(:witness, witness.id),
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp turn(ctx), do: %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.lily}
  defp run(name, args, ctx), do: Tools.run(name, Jason.encode!(args), turn(ctx))

  test "the resident writes a scratch pad, reads it, and removes it when its work is done", ctx do
    assert run(
             "document_write",
             %{path: "scratch/yc-pad.md", content: "# Pad\n\nOpen items."},
             ctx
           ) =~
             "Written scratch/yc-pad.md"

    assert run("library_read", %{path: "scratch/yc-pad.md"}, ctx) =~ "Open items."
    assert File.exists?(Path.join(ctx.dir, "scratch/yc-pad.md"))

    assert run("document_remove", %{path: "scratch/yc-pad.md"}, ctx) ==
             "Removed scratch/yc-pad.md."

    refute File.exists?(Path.join(ctx.dir, "scratch/yc-pad.md"))
    assert run("library_read", %{path: "scratch/yc-pad.md"}, ctx) =~ "Not done"

    assert run("library_search", %{q: "Open items"}, ctx) |> String.contains?("scratch/yc-pad.md") ==
             false

    # Removing what is gone, and anything not removable, is refused.
    assert run("document_remove", %{path: "scratch/yc-pad.md"}, ctx) =~ "Not done"
    {:ok, _} = Seshat.write(ctx.id, "design/plan.md", "# Plan", ctx.lily)

    assert {:error, %Seshat.Error{kind: :seshat_not_removable}} =
             Seshat.remove(ctx.id, "design/plan.md", ctx.lily)

    assert {:error, %Seshat.Error{kind: :seshat_not_removable}} =
             Seshat.remove(ctx.id, "design/plan.md", ctx.witness)
  end

  test "human/ is the witness's: the resident reads it and never writes or removes it", ctx do
    assert run("document_write", %{path: "human/substack-post.md", content: "mine"}, ctx) =~
             "Not done"

    assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
             Seshat.write(ctx.id, "human/substack-post.md", "mine", ctx.lily)

    assert {:ok, %{kind: "human"}} =
             Seshat.write(
               ctx.id,
               "human/substack-post.md",
               "# A post of his\n\nOn Haven.",
               ctx.witness
             )

    assert run("library_read", %{path: "human/substack-post.md"}, ctx) =~ "On Haven."

    assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
             Seshat.remove(ctx.id, "human/substack-post.md", ctx.lily)

    assert :ok = Seshat.remove(ctx.id, "human/substack-post.md", ctx.witness)
    refute File.exists?(Path.join(ctx.dir, "human/substack-post.md"))

    # The resident's tool description never offers human/ as hers to write.
    write = Enum.find(Tools.definitions(), &(&1.function.name == "document_write"))
    assert write.function.description =~ "scratch"
    refute write.function.description =~ "human"
  end
end
