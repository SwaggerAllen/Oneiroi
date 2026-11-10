defmodule Oneiroi.Seshat.ScenesTest do
  @moduledoc """
  The day's scenes as rows (seshat#52): written one call a scene, the
  day not finished until closed, `scenes/<day>.md` rendered from the
  rows, the three asymmetric edits (facts on any day with the old kept,
  summaries by an appended row, mood same-day and then a marked
  correction), the `scene_write` tool's permission and dispatch, and the
  best-effort backfill of prose days.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock.Fake, as: Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Scenes

  @day "2026-10-26"

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    turn = %{
      resident_id: resident.id,
      session_key: nil,
      turn_ref: nil,
      started_at: ~U[2026-10-26 12:00:00.000000Z],
      resident: brain
    }

    {:ok, id: resident.id, brain: brain, dir: dir, turn: turn}
  end

  defp scene(extra \\ %{}) do
    Map.merge(
      %{
        "day" => @day,
        "title" => "The morning check-in",
        "from_turn" => "aaaaaaaaaaaaaaaa",
        "to_turn" => "bbbbbbbbbbbbbbbb",
        "from_time" => "08:00",
        "to_time" => "08:40",
        "summary" => "He asked how the night went; I told him.",
        "mood" => "quiet, glad",
        "register" => "his"
      },
      extra
    )
  end

  defp write(ctx, args), do: Seshat.scene_write(ctx.id, args, ctx.brain)

  defp rows(ctx, day \\ @day) do
    case Seshat.scenes(ctx.id, day, day) do
      [d] -> d
      [] -> nil
    end
  end

  defp file(ctx, day \\ @day), do: File.read!(Path.join(ctx.dir, "scenes/#{day}.md"))

  test "scenes are numbered within their day; the day reads not finished until final closes it, in the rows and in the file",
       ctx do
    assert {:ok, %{number: 1, done: "written", complete: false}} = write(ctx, scene())
    assert %{complete: false, scenes: [%{number: 1, title: "The morning check-in"}]} = rows(ctx)
    assert file(ctx) =~ "Not finished"
    assert file(ctx) =~ "## 1. The morning check-in"

    assert file(ctx) =~
             "08:00–08:40 · turns `aaaaaaaaaaaaaaaa` to `bbbbbbbbbbbbbbbb` · his words · mood: quiet, glad"

    assert file(ctx) =~ "He asked how the night went; I told him."

    assert {:ok, %{number: 2, complete: true}} =
             write(
               ctx,
               scene(%{
                 "title" => "Building",
                 "register" => "work",
                 "rounds_ran_out" => true,
                 "mood" => nil,
                 "final" => true
               })
             )

    assert %{
             complete: true,
             closed_at: %DateTime{},
             scenes: [_, %{number: 2, rounds_ran_out: true}]
           } =
             rows(ctx)

    refute file(ctx) =~ "Not finished"
    assert file(ctx) =~ "## 2. Building"
    assert file(ctx) =~ "The tool rounds ran out on this scene."

    # The file is a registered document of the platform's scenes kind,
    # never hers to write by hand.
    assert {:error, %{kind: :seshat_kind_not_writable}} =
             Seshat.write(ctx.id, "scenes/#{@day}.md", "# mine", ctx.brain)

    # A pass that ends short: another day, written and never closed.
    {:ok, _} = write(ctx, scene(%{"day" => "2026-10-25"}))
    assert %{complete: false} = rows(ctx, "2026-10-25")

    # Closing alone, once the last scene is written; again is a no-op.
    assert {:ok, %{done: "closed", complete: true}} =
             write(ctx, %{"day" => "2026-10-25", "final" => true})

    assert {:ok, %{done: "closed", complete: true}} =
             write(ctx, %{"day" => "2026-10-25", "final" => true})
  end

  test "facts are corrected on any day, the old values kept in the history", ctx do
    {:ok, _} = write(ctx, scene())
    Clock.put(~U[2026-10-29 12:00:00.000000Z])

    assert {:error, %{kind: :seshat_scene_invalid}} =
             write(ctx, %{"day" => @day, "scene" => 1, "title" => "Check-in"})

    assert {:ok, %{done: "corrected", number: 1}} =
             write(ctx, %{
               "day" => @day,
               "scene" => 1,
               "title" => "The first check-in",
               "to_turn" => "cccccccccccccccc",
               "to_time" => "09:10",
               "note" => "it ran on past the kettle"
             })

    assert %{
             scenes: [
               %{
                 title: "The first check-in",
                 to_turn: "cccccccccccccccc",
                 to_time: ~U[2026-10-26 09:10:00.000000Z],
                 corrected_at: ~U[2026-10-29 12:00:00.000000Z]
               }
             ]
           } = rows(ctx)

    {:ok, events} = Oneiroi.EventStore.read_stream_forward("scenes-" <> ctx.id)

    assert %Seshat.Events.SceneCorrected{note: "it ran on past the kettle"} =
             corrected = Enum.at(events, 1).data

    assert %{
             "title" => "The morning check-in",
             "to_turn" => "bbbbbbbbbbbbbbbb",
             "to_time" => "2026-10-26T08:40:00Z"
           } = Seshat.Scene.texts(corrected.was)

    assert %{"title" => "The first check-in"} = Seshat.Scene.texts(corrected.changes)

    assert file(ctx) =~ "## 1. The first check-in"
    assert file(ctx) =~ "Facts corrected 2026-10-29"

    # The same values again move nothing.
    assert {:ok, %{done: "unchanged"}} =
             write(ctx, %{
               "day" => @day,
               "scene" => 1,
               "title" => "The first check-in",
               "note" => "again"
             })

    assert {:error, %{kind: :seshat_no_such_scene}} =
             write(ctx, %{"day" => @day, "scene" => 9, "title" => "x", "note" => "n"})
  end

  test "a summary is never overwritten: its correction is a row of its own citing its turns",
       ctx do
    {:ok, _} = write(ctx, scene())

    assert {:error, %{kind: :seshat_scene_summary_kept}} =
             write(ctx, %{
               "day" => @day,
               "scene" => 1,
               "summary" => "Something else.",
               "note" => "wrong"
             })

    assert {:ok, %{done: "summary_corrected", number: 2, corrects: 1}} =
             write(ctx, %{
               "day" => @day,
               "corrects" => 1,
               "from_turn" => "aaaaaaaaaaaaaaaa",
               "to_turn" => "aaaaaaaaaaaaaaaa",
               "summary" => "He asked first; I answered after the tea.",
               "note" => "the order was the other way"
             })

    assert %{
             scenes: [
               %{number: 1, kind: "scene", summary: "He asked how the night went; I told him."},
               %{number: 2, kind: "correction", corrects: 1, from_turn: "aaaaaaaaaaaaaaaa"}
             ]
           } = rows(ctx)

    assert file(ctx) =~ "He asked how the night went; I told him."
    assert file(ctx) =~ "### Correction to scene 1 (row 2"
    assert file(ctx) =~ "He asked first; I answered after the tea."

    # A correction cites its turns and says why.
    assert {:error, %{kind: :seshat_scene_invalid}} =
             write(ctx, %{"day" => @day, "corrects" => 1, "summary" => "x", "note" => "n"})

    assert {:error, %{kind: :seshat_scene_invalid}} =
             write(ctx, %{
               "day" => @day,
               "corrects" => 1,
               "from_turn" => "a",
               "to_turn" => "a",
               "summary" => "x"
             })
  end

  test "the mood moves freely on the day it was written, and after that only as a marked correction",
       ctx do
    {:ok, _} = write(ctx, scene())

    assert {:ok, %{done: "corrected", mood_correction: false}} =
             write(ctx, %{"day" => @day, "scene" => 1, "mood" => "quiet", "note" => "truer"})

    assert %{scenes: [%{mood: "quiet", mood_was: nil, mood_corrected_at: nil}]} = rows(ctx)
    assert file(ctx) =~ "mood: quiet\n"

    Clock.put(~U[2026-10-27 12:00:00.000000Z])

    assert {:ok, %{done: "corrected", mood_correction: true}} =
             write(ctx, %{"day" => @day, "scene" => 1, "mood" => "tired", "note" => "it was"})

    assert %{
             scenes: [
               %{
                 mood: "tired",
                 mood_was: "quiet",
                 mood_corrected_at: ~U[2026-10-27 12:00:00.000000Z]
               }
             ]
           } = rows(ctx)

    assert file(ctx) =~ "mood: tired (a correction, 2026-10-27; first written: quiet)"

    # A later correction keeps the first-written mood it was corrected from.
    Clock.put(~U[2026-10-28 12:00:00.000000Z])
    {:ok, _} = write(ctx, %{"day" => @day, "scene" => 1, "mood" => "spent", "note" => "more so"})
    assert %{scenes: [%{mood: "spent", mood_was: "quiet"}]} = rows(ctx)
  end

  test "the tool is a write, offered on every path, dispatched to the rows, and mocked in a trial",
       ctx do
    assert "scene_write" in Tools.writes()
    refute "scene_write" in Tools.reads()
    assert Enum.any?(Tools.definitions_for(ctx.id), &(&1.function.name == "scene_write"))

    answer = Tools.run("scene_write", Jason.encode!(scene()), ctx.turn)
    assert answer =~ "Wrote scene 1 of #{@day} into scenes/#{@day}.md."
    assert answer =~ "not finished"
    assert %{scenes: [%{title: "The morning check-in"}]} = rows(ctx)

    assert Tools.run(
             "scene_write",
             Jason.encode!(%{"day" => @day, "scene" => 1, "summary" => "x", "note" => "n"}),
             ctx.turn
           ) =~
             Tools.not_done()

    # A trial answers as the write would, and writes nothing.
    {mocked, _turn} =
      Tools.trial("scene_write", Jason.encode!(scene(%{"final" => true})), ctx.turn)

    assert mocked =~ "Wrote scene 2 of #{@day}"
    assert mocked =~ "The day is finished."
    assert %{complete: false, scenes: [_]} = rows(ctx)
  end

  test "the backfill reads clean prose days into closed rows and leaves the rest as prose", ctx do
    folder = Path.join(ctx.dir, "scenes")
    File.mkdir_p!(folder)

    clean = """
    # Scenes of 2026-10-20

    ## 1. Morning check-in (08:02–08:40)

    Turns [aaaaaaaaaaaaaaaa] to [bbbbbbbbbbbbbbbb]
    Mood: easy

    He asked how the night went.
    I told him about the dream.

    ## The long build · 09:15 – 11:30

    `cccccccccccccccc` … `dddddddddddddddd`

    We built the navigator's paging.
    """

    messy = """
    Today was a lot. I'm writing this as one piece.

    ## Morning

    He asked how the night went.
    """

    File.write!(Path.join(folder, "2026-10-20.md"), clean)
    File.write!(Path.join(folder, "2026-10-21.md"), messy)

    assert {:ok, %{rows: [{"2026-10-20", 2}], prose: [{"2026-10-21", _}]}} =
             Seshat.backfill_scenes(ctx.id, Actor.platform(), dry_run: true)

    assert [] = Seshat.scenes(ctx.id, nil, nil)

    assert {:ok, %{rows: [{"2026-10-20", 2}], prose: [{"2026-10-21", why}], skipped: []}} =
             Seshat.backfill_scenes(ctx.id, Actor.platform(), [])

    assert why =~ "prose"

    assert %{
             complete: true,
             scenes: [
               %{
                 title: "Morning check-in",
                 from_turn: "aaaaaaaaaaaaaaaa",
                 to_turn: "bbbbbbbbbbbbbbbb",
                 from_time: ~U[2026-10-20 08:02:00.000000Z],
                 to_time: ~U[2026-10-20 08:40:00.000000Z],
                 mood: "easy",
                 summary: "He asked how the night went.\nI told him about the dream."
               },
               %{
                 title: "The long build",
                 from_turn: "cccccccccccccccc",
                 to_turn: "dddddddddddddddd",
                 summary: "We built the navigator's paging."
               }
             ]
           } = rows(ctx, "2026-10-20")

    assert file(ctx, "2026-10-20") =~ "## 1. Morning check-in"
    assert file(ctx, "2026-10-21") == messy

    assert {:ok, %{rows: [], skipped: ["2026-10-20"]}} =
             Seshat.backfill_scenes(ctx.id, Actor.platform(), [])
  end

  test "parse: a scene that cites no turn keeps the day prose" do
    assert {:prose, "scene 1: cites no turn"} =
             Scenes.parse("2026-10-20", "## Morning\n\nHe asked.\n", "Etc/UTC")

    assert {:prose, "no scene headings"} = Scenes.parse("2026-10-20", "# Title\n", "Etc/UTC")
  end
end
