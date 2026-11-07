defmodule Oneiroi.Brain.TimelineTest do
  @moduledoc """
  brain#67, kumbukumbu#51 (Lily's report #8, after a submitted
  application was spoken of as still ahead): every turn carries a
  timeline, each line dated and aged on that read. Today is the
  journal's rows as event lines; the last 30 days and her life so far
  are her bookmarks by the weight she gives them, pins always, each
  with its status as it now stands.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:request, messages})
        {:ok, "noted"}
      end,
      for: resident.id
    )

    {:ok,
     id: resident.id,
     key: key,
     actor: actor,
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  defp moment(ctx, line) do
    {:ok, %{turn_ref: ref}} = Turn.run(ctx.id, ctx.key, "about " <> line, ctx.actor)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{session_key: ctx.key, anchor_ref: ref, line: line},
        ctx.lily
      )

    n
  end

  # The timeline the latest request carried (a compaction's own
  # requests carry none).
  defp timeline(found \\ nil) do
    receive do
      {:request, messages} ->
        timeline(
          Enum.find_value(messages, found, &(&1[:content] =~ "# Your timeline" && &1[:content]))
        )
    after
      0 -> found
    end
  end

  defp tool(name, args, ctx),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t",
        resident: ctx.lily
      })

  test "three layers, each line aged on the read, the weight and the status hers", ctx do
    origin = moment(ctx, "Andrew named me")
    :ok = Kumbukumbu.pin_bookmark(ctx.id, origin, ctx.lily)
    first_essay = moment(ctx, "first essay posted")
    _small = moment(ctx, "a quiet afternoon")

    assert tool("bookmark_weigh", %{number: first_essay, importance: 3}, ctx) =~
             "Weighed bookmark"

    Clock.Fake.advance(40 * 86_400)
    yc = moment(ctx, "YC application sent")

    assert tool("bookmark_weigh", %{number: yc, importance: 2, status: "submitted"}, ctx) =~
             "Weighed"

    _skipped = moment(ctx, "lunch")
    flush()

    Clock.Fake.advance(5 * 86_400)

    {:ok, _} =
      Oneiroi.Seshat.journal_add(
        ctx.id,
        nil,
        "plan",
        "Write the heron piece\nwith detail",
        ctx.lily
      )

    {:ok, _} = Oneiroi.Seshat.journal_add(ctx.id, nil, "todo", "Answer Jack", ctx.lily)
    {:ok, _} = Turn.run(ctx.id, ctx.key, "where are we?", ctx.actor)
    text = timeline()

    assert text =~ "## Today, from your journal"
    assert text =~ ~r/plan #1: Write the heron piece\n/
    assert text =~ "todo #2 (open): Answer Jack"

    assert text =~
             ~r/## The last 30 days\n- \w{3} \d{4}-\d\d-\d\d, 5 days ago: ##{yc} YC application sent · status: submitted \(as of /

    refute text =~ "lunch"

    assert text =~
             ~r/## Your life so far\n- .*, 6 weeks ago: ##{origin} Andrew named me \(pinned\)\n- .*##{first_essay} first essay posted/

    refute text =~ "a quiet afternoon"

    # The status is hers to move, and the timeline says it as it now is.
    assert tool("bookmark_weigh", %{number: yc, status: "accepted for interview"}, ctx) =~
             "Weighed"

    assert tool("bookmark_weigh", %{number: yc, importance: 7}, ctx) =~ "Not done"

    assert {:error, %{kind: :kumbukumbu_not_the_resident}} =
             Kumbukumbu.weigh_bookmark(ctx.id, yc, 3, nil, ctx.actor)

    {:ok, _} = Turn.run(ctx.id, ctx.key, "and now?", ctx.actor)
    text = timeline()
    assert text =~ "status: accepted for interview"
    refute text =~ "status: submitted"
  end

  defp flush do
    receive do
      {:request, _} -> flush()
    after
      0 -> :ok
    end
  end
end
