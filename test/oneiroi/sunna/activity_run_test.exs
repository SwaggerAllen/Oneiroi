defmodule Oneiroi.Sunna.ActivityRunTest do
  @moduledoc """
  The work loop on the house queue (sunna#86): after the cutover, an
  armed line runs her ready activities a turn at a time, under the same
  line, care and cap as items; the run ends as soon as she records the
  activity with her queue tools, and the next check starts the next of
  hers or rests saying why. Before the cutover the line runs items.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.WorkLoop

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    Fixtures.agreed!(resident.id, witness.id)
    andrew = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    test = self()
    me = Actor.new(:resident, resident.id, "fake/model")
    h = witness.id

    :ok = Sunna.queue_open_project(h, %{slug: "p", name: "P"}, me)

    {:ok, n} =
      Sunna.queue_open_task(
        h,
        %{
          project: "p",
          slug: "brief",
          title: "The brief",
          outcome: "drafted for his read",
          layers: [
            [%{type: "draft", assignee: "resident:#{resident.id}"}],
            [%{type: "review", assignee: "witness:#{witness.id}"}]
          ]
        },
        me
      )

    # She drafts, then records it done with her queue tool.
    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})
        last = List.last(request.messages)[:content] || ""

        if request.tool_choice == "none" or last =~ "recorded" do
          {:ok, "Drafted and recorded."}
        else
          {:calls,
           [
             %{
               name: "queue_move",
               arguments: %{task: n, act: "#{n}.1", move: "finish", note: "drafted"}
             }
           ]}
        end
      end,
      for: resident.id
    )

    %{id: resident.id, h: h, n: n, me: me, andrew: andrew}
  end

  defp jobs(id) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job, where: j.worker == "Oneiroi.Sunna.WorkWorker", select: j.args)
      )
    end)
    |> Enum.filter(&(&1["resident_id"] == id))
  end

  defp clear_jobs do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.delete_all(from(j in Oban.Job, where: j.worker == "Oneiroi.Sunna.WorkWorker"))
    end)
  end

  test "after the cutover the line runs her ready activity, and her recording it ends the run",
       ctx do
    n = ctx.n
    :ok = Sunna.queue_cut_over(ctx.h, "abc1234", "the set is built", ctx.andrew)

    # Old items are read-only; the line itself still arms.
    assert {:error, %{kind: :sunna_work_frozen}} = Sunna.work_add(ctx.id, "x", "y", ctx.me)
    :ok = Sunna.work_arm(ctx.id, ctx.me)
    assert WorkLoop.due?(ctx.id)
    clear_jobs()

    act = "#{n}.1"
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    assert :running = WorkLoop.check(ctx.id)

    # Taken at the run's start: hers, active.
    assert %{view: "active"} =
             Enum.find(List.flatten(Sunna.queue_task(ctx.h, n).layers), &(&1.act_id == act))

    [%{"session_key" => key, "act" => ^act, "turn" => 1, "household" => h}] = jobs(ctx.id)
    assert h == ctx.h
    clear_jobs()

    # Turn 1: the note names the activity and its task; she finishes it,
    # and the run ends there, with no closing turn, asking for a check.
    assert :ok = WorkLoop.activity_turn(ctx.id, key, ctx.h, n, act, 1)
    assert_received {:asked, first}

    note =
      Enum.find(first, &(is_binary(&1[:content]) and &1.content =~ "a run of your work line"))

    assert note.content =~ "activity #{act}"
    assert note.content =~ "drafted for his read"

    assert %{status: "done"} =
             Enum.find(List.flatten(Sunna.queue_task(ctx.h, n).layers), &(&1.act_id == act))

    assert [%{"turn" => "check"}] = jobs(ctx.id)

    # Nothing else is hers (the review is his): the line goes off, saying why.
    assert {:rested, "empty, holding: nothing in the house queue is ready for you"} =
             WorkLoop.check(ctx.id)

    refute WorkLoop.due?(ctx.id)
  end

  test "before the cutover the line is the old queue's", ctx do
    :ok = Sunna.work_arm(ctx.id, ctx.me)

    assert {:rested, "empty, holding"} = WorkLoop.check(ctx.id)
  end
end
