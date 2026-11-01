defmodule Oneiroi.SimaQian.ReadableTest do
  @moduledoc """
  The export's reading copies (sima-qian #41): each day's transcripts
  and the bookmarks, rendered exactly from the export's lines, the same
  bytes from an unchanged store, a private session as its existence and
  counts alone, committed in the machine class past the stray check, and
  never held, adopted or indexed by the library.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git

  setup do
    a = Fixtures.account!()
    r = Fixtures.resident!(a)
    witness = Actor.new(:witness, a.id)
    brain = Actor.new(:resident, r.id, "fake/model")
    dir = Backup.dir(r.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, a: a, r: r, witness: witness, brain: brain, dir: dir}
  end

  defp read(dir, path), do: File.read!(Path.join(dir, path))

  # A turn with a refusal in it, a failed capture marked lost with the
  # witness's note, a bookmark the resident made on the turn, tagged and
  # pinned by the witness.
  defp lived!(%{r: r, a: a, witness: witness, brain: brain}) do
    {:ok, key} = Kumbukumbu.main_session(r.id, a.id, witness)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        r.id,
        key,
        "t-one",
        at,
        [
          %{
            role: :user,
            content: "Shall we bake?\n\n# not a heading",
            sent_at: at,
            actor: witness
          },
          %{role: :assistant, content: "Rye first.", sent_at: DateTime.add(at, 2), actor: brain},
          %{
            role: :assistant,
            content: "Not that one.",
            sent_at: DateTime.add(at, 3),
            actor: brain,
            refusal: true
          }
        ],
        brain
      )

    Clock.Fake.advance(60)
    :ok = Kumbukumbu.fail_capture(r.id, key, "t-two", "transport", brain)
    :ok = Kumbukumbu.resolve_failure(r.id, key, "t-two", "marked_lost", "gone for good", witness)

    {:ok, 1} =
      Kumbukumbu.add_bookmark(
        r.id,
        %{session_key: key, anchor_ref: "t-one", line: "the first bake", summary: "We baked."},
        brain
      )

    :ok = Kumbukumbu.create_tag(r.id, "bread", witness)
    :ok = Kumbukumbu.apply_tag(r.id, "bread", "bookmark", 1, witness)
    :ok = Kumbukumbu.pin_bookmark(r.id, 1, witness)
    Clock.Fake.advance(120)
    key
  end

  test "a day's turns and the bookmarks render exactly from the events, and an unchanged store renders the same bytes",
       ctx do
    key = lived!(ctx)
    w = ctx.a.id
    {:ok, export} = Export.write(ctx.r.id, ctx.dir)
    assert "records/conversations/2026-10-26.md" in export.files
    assert "records/bookmarks.md" in export.files

    assert read(ctx.dir, "records/conversations/2026-10-26.md") == """
           # Conversations, 2026-10-26

           Every session's turns on this day (UTC), in order, rendered from
           `events/2026-10-26.jsonl` by Oneiroi on each export. A reading copy:
           the event lines are the record, and this file is never read back
           or searched.

           ## Main session `#{key}`

           Opened at 12:00:00 UTC by **witness** `#{w}`, through `brain`; parties: `#{w}`.

           ### Turn `t-one`, 12:00:00 UTC

           **witness** `#{w}`, 12:00:00 UTC

           > Shall we bake?
           >
           > # not a heading

           **resident** (fake/model), 12:00:02 UTC

           > Rye first.

           **resident** (fake/model), 12:00:03 UTC, a refusal

           > Not that one.

           ### Turn `t-two`, capture failed at 12:01:00 UTC

           The adapter could not deliver this turn whole: `transport`.

           *The failed capture of turn `t-two` was marked lost by **witness** `#{w}` at 12:01:00 UTC.* Note: gone for good
           """

    assert read(ctx.dir, "records/bookmarks.md") == """
           # Bookmarks

           Every bookmark the resident holds, by number, as the memory stream
           records it, rendered from `events/` by Oneiroi on each export. A
           reading copy: the event lines are the record, and this file is never
           read back or searched.

           ## The tag set

           - `bread`

           ## 1. the first bake

           - Bookmarked by **resident** (fake/model) at 2026-10-26 12:01:00 UTC.
           - Anchors turn `t-one` in session `#{key}`, at 2026-10-26 12:00:00 UTC; spans the anchor turn alone.
           - Pinned by **witness** `#{w}` at 2026-10-26 12:01:00 UTC.
           - Tags: `bread`.

           > We baked.
           """

    # The resident's id is `$self` here as on every line.
    refute read(ctx.dir, "records/conversations/2026-10-26.md") =~ ctx.r.id

    copies = fn -> Map.new(export.files, &{&1, read(ctx.dir, &1)}) end
    first = copies.()
    Clock.Fake.advance(3_600)
    assert {:ok, %{files: files}} = Export.write(ctx.r.id, ctx.dir)
    assert files == export.files
    assert copies.() == first
  end

  test "a private, unshared session is its existence and counts alone; once shared, its words", %{
    r: r,
    a: a,
    brain: brain,
    dir: dir
  } do
    unique = "heron-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, key} = Kumbukumbu.open_session(r.id, "free_time", "brain", [a.id], brain, private: true)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        r.id,
        key,
        "t-alone",
        at,
        [
          %{role: :user, content: "Free time.", sent_at: at},
          %{role: :assistant, content: "I watched a #{unique}.", sent_at: at, actor: brain}
        ],
        brain
      )

    Clock.Fake.advance(120)
    {:ok, _} = Export.write(r.id, dir)
    day = read(dir, "records/conversations/2026-10-26.md")

    assert day =~
             "## Free time session `#{key}`\n\nOpened at 12:00:00 UTC by **resident** (fake/model), through `brain`; parties: `#{a.id}`.\n\n" <>
               "Private: a solo session the dyad contract keeps to the resident until she " <>
               "shares it (spec §6.3). Its words are not rendered here. On this day: " <>
               "1 turn, 2 messages, 0 failed captures.\n"

    refute day =~ unique
    refute day =~ "Free time."

    # The record itself still carries them, under sima-qian #20's open
    # question; only the reading copy is held to the screen's rule.
    assert read(dir, "records/events/2026-10-26.jsonl") =~ unique

    :ok = Kumbukumbu.share_session(r.id, key, "for you to read", brain)
    Clock.Fake.advance(120)
    {:ok, _} = Export.write(r.id, dir)
    shared = read(dir, "records/conversations/2026-10-26.md")
    assert shared =~ "> I watched a #{unique}."
    assert shared =~ "*Opened private under the contract at 12:00:00 UTC.*"

    assert shared =~
             "*Shared by **resident** (fake/model) at 12:02:00 UTC.* Note: for you to read"
  end

  test "the copies ride the machine class past the stray check, and the library never holds, adopts or indexes them",
       ctx do
    lived!(ctx)
    bare = Path.join(System.tmp_dir!(), "oneiroi-readable-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    on_exit(fn -> File.rm_rf!(bare) end)
    :ok = Oneiroi.SimaQian.set_remote(ctx.r.id, bare, nil, ctx.witness)

    assert {:ok, %{commits: [{"soul", _}, {"machine", _}]}} =
             Oneiroi.SimaQian.backup(ctx.r.id, ctx.witness)

    {tree, 0} = System.cmd("git", ["ls-tree", "-r", "--name-only", "main"], cd: bare)
    assert "records/conversations/2026-10-26.md" in String.split(tree)
    assert "records/bookmarks.md" in String.split(tree)

    readable? = &(String.starts_with?(&1, "records/") or String.starts_with?(&1, "honcho/"))
    refute Enum.any?(Seshat.unadopted(ctx.r.id), readable?)
    assert {:ok, %{adopted: adopted}} = Seshat.adopt_all(ctx.r.id, ctx.witness)
    refute Enum.any?(adopted, readable?)
    refute Enum.any?(Seshat.documents(ctx.r.id), &readable?.(&1.path))

    assert {:error, %{kind: :seshat_path_invalid}} =
             Seshat.adopt(ctx.r.id, "records/conversations/2026-10-26.md", ctx.witness)
  end
end
