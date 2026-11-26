defmodule Oneiroi.Sunna.ActivityRunTest do
  @moduledoc """
  The work loop on the house queue (sunna#86, #102): her line runs her
  ready activities a turn at a time, under its care and caps; the run
  ends as soon as she records the activity with her queue tools, and the
  next check starts the next of hers or rests saying why.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYou.WorkStopped
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.WorkLoop
  alias Oneiroi.Sunna.WorkRouter

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

  test "the line runs her ready activity, and her recording it ends the run",
       ctx do
    n = ctx.n

    # The house queue runs unless paused, with no arm of hers (sunna#94):
    # paused, nothing starts; resumed, it does.
    assert WorkLoop.due?(ctx.id)

    assert {:error, %{kind: :sunna_queue_not_yours}} =
             Sunna.queue_pause(ctx.h, "mine to stop", Oneiroi.Actor.new(:resident, ctx.id))

    :ok = Sunna.queue_pause(ctx.h, "a quiet evening", ctx.andrew)
    refute WorkLoop.due?(ctx.id)
    assert {:rested, "paused: the house queue is paused"} = WorkLoop.check(ctx.id)
    :ok = Sunna.queue_resume(ctx.h, "back to it", ctx.andrew)
    assert WorkLoop.due?(ctx.id)
    clear_jobs()

    act = "#{n}.1"
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    assert :running = WorkLoop.check(ctx.id)

    # Its card says her line is working it (2026-11-23).
    assert %{line: %{state: "running"}} =
             Enum.find(Sunna.queue_activities(ctx.h, %{}), &(&1.act == act))

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

    # Nothing else is hers (the review is his): the queue still runs and
    # her line holds, saying why (sunna#92, #94), not due until something is.
    assert {:rested, "running, holding: nothing of yours is ready in what is open"} =
             WorkLoop.check(ctx.id)

    refute WorkLoop.due?(ctx.id)
  end

  # sunna#109 (the witness, 2026-11-26: the line stalled after a stop
  # with nothing on the task, its thread or the bell): a stopped run
  # fails its activity, rests the line, names who on his bell, and only
  # a resume takes the line up again.
  test "a stopped run fails its activity, rests the line on his bell, and a resume takes it up",
       ctx do
    n = ctx.n
    act = "#{n}.1"
    Fake.script(fn _ -> {:ok, "Too much. OUROBOROS"} end, for: ctx.id)
    clear_jobs()

    assert {:started, ^act} = WorkLoop.check(ctx.id)
    [%{"session_key" => key}] = jobs(ctx.id)
    clear_jobs()

    # The session is named for what proc'd it.
    assert %{label: label} =
             Enum.find(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.key == key))

    assert label =~ "##{n} The brief · "

    assert :ok = WorkLoop.activity_turn(ctx.id, key, ctx.h, n, act, 1)

    # Failed where the house reads it, its words not saying who.
    assert %{view: "failed", reason: what} =
             Enum.find(List.flatten(Sunna.queue_task(ctx.h, n).layers), &(&1.act_id == act))

    assert what =~ "Stopped mid-run"
    refute what =~ "safe word"

    # The line rests, and his bell says why and who, with the run's place.
    assert :stopped = WorkLoop.check(ctx.id)
    refute WorkLoop.due?(ctx.id)

    assert %{act: ^act, task: ^n, by: "safe_word", session_key: ^key} =
             Sunna.work_stopped(ctx.id)

    assert [%{kind: "work_stopped", about: %{words: words, task: ^n}}] =
             WorkStopped.entries(ctx.id)

    assert words =~ "safe word"

    # Only a party resumes it; then it checks again, and the bell clears.
    assert {:error, %{kind: :sunna_work_not_a_party}} =
             Sunna.work_resume(ctx.id, "go", Actor.new(:job, "x"))

    assert :ok = Sunna.work_resume(ctx.id, "taken up again", ctx.andrew)
    assert nil == Sunna.work_stopped(ctx.id)
    assert [] = WorkStopped.entries(ctx.id)
    refute WorkLoop.check(ctx.id) == :stopped
  end

  # sunna#100 (the witness, 2026-11-24: "if the server restarts during a
  # work item run, have we handled restarting the work?"): a crash leaves
  # the turn's job executing; past any turn's length it is taken for
  # orphaned, the run is ended as cut, and the activity runs again in a
  # new conversation that is told where the cut-off run was.
  test "a run whose job a crash left executing is ended as cut, and the next run is told", ctx do
    n = ctx.n
    act = "#{n}.1"
    clear_jobs()
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    [%{"session_key" => first}] = jobs(ctx.id)

    # The crash: its turn's job says executing, and stays so.
    executing(first, Clock.now())
    Clock.Fake.advance(5 * 60)
    assert :running = WorkLoop.check(ctx.id)
    refute WorkLoop.due?(ctx.id)

    # Executing longer than any turn: orphaned, so the run is ended.
    executing(first, DateTime.add(Clock.now(), -20 * 60, :second))
    assert WorkLoop.due?(ctx.id)
    assert :stalled = WorkLoop.check(ctx.id)
    assert %{cut: %{act: ^act, key: ^first}} = Sunna.work_queue(ctx.id)

    # Still hers and active: the next check runs it again, in a new
    # conversation, whose first turn names the cut-off one.
    clear_jobs()
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    [%{"session_key" => second}] = jobs(ctx.id)
    assert second != first
    assert :ok = WorkLoop.activity_turn(ctx.id, second, ctx.h, n, act, 1)
    assert_received {:asked, messages}

    note =
      Enum.find(messages, &(is_binary(&1[:content]) and &1.content =~ "a run of your work line"))

    assert note.content =~ "Your last run of this activity was cut off"
    assert note.content =~ first

    # She finished it this time: a run that ends on its own clears the cut.
    assert %{cut: nil} = Sunna.work_queue(ctx.id)
  end

  # sunna#101 (the witness, 2026-11-24: "20 per work item to stop
  # runaway loops"), sunna#106 (2026-11-25: "A task that's out of runs
  # should be blocked", the give-back on its task): an activity run twenty
  # times with nothing moving is blocked on the queue, said why, and the
  # line goes on; the witness gives its runs back on its task, which opens
  # it again; a run that moves it starts its count over.
  test "an activity out of runs is blocked, and its runs given back on its task open it again",
       ctx do
    n = ctx.n
    act = "#{n}.1"

    for _ <- 1..20 do
      assert {:started, ^act} = WorkLoop.check(ctx.id)
      end_run(ctx.id, act, false)
    end

    assert %{activity_runs: [%{act: ^act, runs: 20}], runs_an_activity: 20, runs_a_day: 1000} =
             Sunna.work_queue(ctx.id)

    assert :blocked_spent = WorkLoop.check(ctx.id)
    %{layers: layers} = Sunna.queue_task(ctx.h, n)
    blocked = layers |> List.flatten() |> Enum.find(&(&1.act_id == act))
    assert blocked.status == "blocked"
    assert blocked.reason =~ "out of runs: 20 runs with nothing moving"

    # Nothing else of hers is ready: the line says so, and is not held.
    assert {:rested, "running, holding: nothing of yours is ready" <> _} = WorkLoop.check(ctx.id)

    # Hers alone to refuse; his, on the task, opens it again.
    assert {:error, _} =
             Sunna.queue_runs_back(ctx.h, n, act, "mine", Actor.new(:resident, ctx.id))

    :ok = Sunna.queue_runs_back(ctx.h, n, act, "go again", ctx.andrew)
    assert %{activity_runs: []} = Sunna.work_queue(ctx.id)
    assert {:started, ^act} = WorkLoop.check(ctx.id)

    # A run that ends with the activity moved starts its count over.
    end_run(ctx.id, act, true)
    assert %{activity_runs: []} = Sunna.work_queue(ctx.id)
  end

  defp end_run(id, act, moved) do
    {:ok, [_]} =
      WorkRouter.dispatch(%Commands.EndActivityRun{
        actor: Actor.platform(),
        at: Clock.now(),
        id: id,
        act: act,
        moved: moved
      })
  end

  defp executing(key, at) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.update_all(
        from(j in Oban.Job,
          where:
            j.worker == "Oneiroi.Sunna.WorkWorker" and
              fragment("? ->> 'session_key' = ?", j.args, ^key)
        ),
        set: [state: "executing", attempted_at: at]
      )
    end)
  end

  # brain#115 (the witness, 2026-11-24: three house check-ins in a row
  # reached neither resident): the check-in note names a house queue step
  # of his on her bell, rather than raising on it before any wake is sent.
  test "the check-in's waiting part names a house queue step ready for the witness", ctx do
    :ok = Sunna.queue_finish(ctx.h, ctx.n, "#{ctx.n}.1", %{}, ctx.me)
    part = Oneiroi.Brain.checkin_part(ctx.id, "needs_you")
    assert part =~ "- 1 house queue step(s) of his ready"
  end

  # A document that starts in the house (the witness, 2026-11-23): her
  # share step on it passes itself, said so, and the line looks again.
  test "her share step on a document already in the house passes itself", ctx do
    :ok = Sunna.queue_drop(ctx.h, ctx.n, "not this one", ctx.andrew)
    doc = "house/nest:doc/design/db-access-consent.md"

    {:ok, m} =
      Sunna.queue_open_task(
        ctx.h,
        %{
          project: "p",
          slug: "consent",
          title: "Consent",
          outcome: "built",
          layers: [
            [
              %{
                type: "review",
                assignee: "witness:#{ctx.andrew.id}",
                artifact: doc,
                destination: "house",
                action: "promote-to-house"
              }
            ],
            [
              %{
                type: "promote-to-house",
                assignee: "resident:#{ctx.id}",
                artifact: doc,
                destination: "house",
                optional: true
              }
            ]
          ]
        },
        ctx.me
      )

    :ok =
      Sunna.queue_decide(
        ctx.h,
        m,
        "#{m}.1",
        %{outcome: "approved", pin: "abc1234", note: "fine"},
        ctx.andrew
      )

    clear_jobs()
    share = "#{m}.2"
    # A mechanical step (sunna#104): passed inside the check, with no run.
    assert {:rested, _} = WorkLoop.check(ctx.id)

    assert %{status: "skipped"} =
             Enum.find(List.flatten(Sunna.queue_task(ctx.h, m).layers), &(&1.act_id == share))

    assert [] = jobs(ctx.id)
  end
end
