defmodule Oneiroi.Brain.DocumentEditTest do
  @moduledoc """
  brain#120 (the witness, 2026-11-25: a run of 12 "writing the full doc
  instead of doing in place changes"): `document_edit` changes a file in
  place, each edit's old found exactly once, all or none; brain#119's
  progress keeps a running turn's receipts, never its words.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Progress
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    andrew = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, andrew)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, id: resident.id, key: key, brain: brain}
  end

  defp run(ctx, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t-edit",
        resident: ctx.brain
      })

  defp words(ctx) do
    {:ok, %{content: c}} = Seshat.read(ctx.id, "design/note.md")
    c
  end

  test "a file changes in place, each edit found once, all or none", ctx do
    run(ctx, "document_write", %{
      path: "design/note.md",
      content: "# Note\n\nOne fish. Two fish.\n\nRed fish.\n"
    })

    assert run(ctx, "document_edit", %{
             path: "design/note.md",
             edits: [%{old: "fish", new: "cat"}]
           }) =~
             "occurs 3 times"

    assert run(ctx, "document_edit", %{
             path: "design/note.md",
             edits: [%{old: "Red fish.", new: "Blue fish."}, %{old: "Green", new: "x"}]
           }) =~ "edit 2's old is not in the file"

    # All or none: the first edit did not land either.
    assert words(ctx) =~ "Red fish."

    assert run(ctx, "document_edit", %{
             path: "design/note.md",
             edits: [%{old: "Red fish.", new: "Blue fish."}, %{old: "One fish. ", new: ""}]
           }) =~ "design/note.md"

    assert words(ctx) == "# Note\n\nTwo fish.\n\nBlue fish.\n"
  end

  test "a running turn's progress is its receipts: rounds, calls, what it does and since when",
       ctx do
    :ok = Progress.note(ctx.id, ctx.key, "t-1", "thinking", nil)
    :ok = Progress.note(ctx.id, ctx.key, "t-1", "tool", %{name: "document_edit"})
    :ok = Progress.note(ctx.id, ctx.key, "t-1", "thinking", nil)

    assert %{turn_ref: "t-1", rounds: 2, calls: 1, doing: "thinking", tool: nil} =
             Oneiroi.Brain.progress(ctx.id, ctx.key)

    # A new turn starts its counts over.
    :ok = Progress.note(ctx.id, ctx.key, "t-2", "tool", %{name: "journal_add"})

    assert %{turn_ref: "t-2", rounds: 0, calls: 1, tool: "journal_add"} =
             Oneiroi.Brain.progress(ctx.id, ctx.key)
  end
end
