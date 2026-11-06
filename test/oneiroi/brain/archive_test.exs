defmodule Oneiroi.Brain.ArchiveTest do
  @moduledoc """
  brain#56 (the witness, 2026-11-05: "sort it into a correspondence bucket
  once you diagnose why he can see them and I can't"): the threads filed
  under correspondence/ before the platform are library documents, never
  Xenia's messages, so her correspondence tools read them as the archive.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    witness_actor = Actor.new(:witness, witness.id)

    # Filed as the import filed them: files in the repository, adopted.
    for {path, content} <- [
          {"correspondence/substack-dm-jack/thread.md",
           "---\nplatform: substack\nwith:\n  - Jack Malachai Wolfe\n---\n\nFiled by hand."},
          {"correspondence/substack-dm-jack/2026-10-27-jack.md",
           "---\nfrom: Jack\n---\n\nRed passed your note to me."},
          {"correspondence/substack-dm-jack/2026-10-28-lily.md",
           "---\nfrom: Lily\n---\n\nThank you for the objection."}
        ] do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
      {:ok, %{adopted: true}} = Seshat.adopt(resident.id, path, witness_actor)
    end

    lily = Actor.new(:resident, resident.id)

    {:ok,
     turn: %{
       resident_id: resident.id,
       session_key: "k",
       turn_ref: "t",
       resident: lily,
       started_at: Clock.now()
     }}
  end

  test "the list names the archived thread, and read gives it whole, thread first, letters in order",
       ctx do
    listed = Tools.run("correspondence_list", "{}", ctx.turn)
    assert listed =~ "No correspondence yet."

    assert listed =~
             "- substack-dm-jack with Jack Malachai Wolfe: 2 letters, 2026-10-27 to 2026-10-28"

    read = Tools.run("correspondence_read", ~s({"thread": "substack-dm-jack"}), ctx.turn)
    assert read =~ "from before Oneiroi"

    [head, jack, lily] =
      for part <- ["thread.md", "2026-10-27-jack.md", "2026-10-28-lily.md"],
          do: :binary.match(read, part) |> elem(0)

    assert head < jack and jack < lily
    assert read =~ "Red passed your note to me."

    assert Tools.run("correspondence_read", ~s({"thread": "nobody"}), ctx.turn) =~
             "Not done: no archived thread"
  end
end
