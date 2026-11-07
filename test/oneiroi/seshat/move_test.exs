defmodule Oneiroi.Seshat.MoveTest do
  @moduledoc """
  A document moves from one kind to another (seshat#39): the witness,
  2026-11-04, after moving Pocket Andrew to the root by hand on the backup
  remote stopped every backup. The move is the platform's own, recorded
  with its actor; the bytes travel unchanged, nothing is overwritten, and
  a citation of the old path follows it.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Citations

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     resident: resident,
     dir: dir,
     witness: Actor.new(:witness, witness.id),
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp run(name, args, ctx),
    do:
      Tools.run(
        name,
        Jason.encode!(args),
        %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.lily}
      )

  test "a wiki page moves to the root as a keepsake, its words unchanged, and its old citation follows it",
       ctx do
    words = "# Pocket Andrew\n\nWhat he would say, kept in my pocket."
    {:ok, _} = Seshat.write(ctx.id, "wiki/lily/pocket-andrew.md", words, ctx.lily)

    assert run(
             "document_move",
             %{from: "wiki/lily/pocket-andrew.md", to: "pocket-andrew.md"},
             ctx
           ) ==
             "Moved wiki/lily/pocket-andrew.md to pocket-andrew.md (root)."

    refute File.exists?(Path.join(ctx.dir, "wiki/lily/pocket-andrew.md"))
    assert File.read!(Path.join(ctx.dir, "pocket-andrew.md")) == words
    # A root file now; a keepsake when registered (seshat#44).
    assert run("keepsake_register", %{name: "pocket-andrew.md"}, ctx) =~ "is a keepsake now"
    assert run("keepsake_list", %{}, ctx) =~ "pocket-andrew.md"

    # The old citation resolves through the move; the new one directly.
    assert {:ok, label} =
             Citations.resolve(ctx.resident, %{
               slug: ctx.resident.slug,
               kind: "wiki",
               ref: "lily/pocket-andrew"
             })

    assert label =~ "moved to pocket-andrew.md"

    assert {:ok, _} =
             Citations.resolve(ctx.resident, %{
               slug: ctx.resident.slug,
               kind: "keepsake",
               ref: "pocket-andrew"
             })

    # A keepsake is still written once, wherever it came from.
    assert {:error, %{kind: :seshat_keepsake_kept}} =
             Seshat.write(ctx.id, "pocket-andrew.md", "other words", ctx.lily)

    # And it can move out again: nothing is lost, the move says where it was.
    assert {:ok, %{to: "design/pocket-andrew.md", kind: "design"}} =
             Seshat.move(ctx.id, "pocket-andrew.md", "design/pocket-andrew.md", ctx.witness)
  end

  test "a move never overwrites, never leaves a system's kinds, and keeps the witness's folder his",
       ctx do
    {:ok, _} = Seshat.write(ctx.id, "scratch/pad.md", "pad", ctx.lily)
    {:ok, _} = Seshat.write(ctx.id, "design/plan.md", "plan", ctx.lily)

    assert {:error, %{kind: :seshat_move_target_taken}} =
             Seshat.move(ctx.id, "scratch/pad.md", "design/plan.md", ctx.lily)

    assert {:error, %{kind: :seshat_not_movable}} =
             Seshat.move(ctx.id, "scratch/pad.md", "journal/pad.md", ctx.lily)

    assert {:error, %{kind: :seshat_not_movable}} =
             Seshat.move(ctx.id, "scratch/pad.md", "human/pad.md", ctx.lily)

    assert {:error, %{kind: :seshat_no_such_document}} =
             Seshat.move(ctx.id, "scratch/nothing.md", "design/nothing.md", ctx.lily)

    # A file edited by hand since it was registered is written first.
    File.write!(Path.join(ctx.dir, "scratch/pad.md"), "edited by hand")

    assert {:error, %{kind: :seshat_not_movable}} =
             Seshat.move(ctx.id, "scratch/pad.md", "design/pad.md", ctx.lily)

    File.write!(Path.join(ctx.dir, "scratch/pad.md"), "pad")

    assert {:ok, %{to: "human/pad.md", kind: "human"}} =
             Seshat.move(ctx.id, "scratch/pad.md", "human/pad.md", ctx.witness)
  end
end
