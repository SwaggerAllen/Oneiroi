defmodule Oneiroi.Sunna.WorkLineTest do
  @moduledoc """
  The work line (sunna#33, #86) since the old work queue retired
  (sunna#102): what it keeps of the loop, on her house queue activities.
  The budget brake, care first and the witness's skip, quiet hours that
  no longer hold it, a stop that rests it, a run left behind ended by the
  check, a failed run that waits, the runs given back, a turn that
  outlasts its wait, a leftover turn of an earlier run, and her
  `work_list`.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.WorkLoop
  alias Oneiroi.Sunna.WorkWorker

  defmodule Outlasted do
    @moduledoc false
    # The wake port answering as the session does when the turn outlasts
    # the wait: it runs on in its conversation, and the caller hears so.
    def wake(_resident_id, _key, _note, _purpose),
      do: {:error, %{kind: :brain_wake_outlasted, site: :brain_session_wake_outlasted}}
  end

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

    # She reads and keeps going until asked to close, then says so in words.
    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})

        if request.tool_choice == "none",
          do: {:ok, "Where it stands: still drafting."},
          else: {:calls, [%{name: "bookmark_list", arguments: %{}}]}
      end,
      for: resident.id
    )

    %{id: resident.id, h: h, n: n, act: "#{n}.1", me: me, andrew: andrew}
  end

  defp jobs(id) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job,
          where: j.worker == "Oneiroi.Sunna.WorkWorker",
          select: %{args: j.args, at: j.scheduled_at}
        )
      )
    end)
    |> Enum.filter(&(&1.args["resident_id"] == id))
  end

  defp clear_jobs do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.delete_all(from(j in Oban.Job, where: j.worker == "Oneiroi.Sunna.WorkWorker"))
    end)
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  defp key(id) do
    [%{key: key} | _] = Enum.filter(Kumbukumbu.sessions({:resident, id}), &(&1.kind == "work"))
    key
  end

  defp started(ctx) do
    act = ctx.act
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    key(ctx.id)
  end

  defp free_time_now(ctx) do
    :ok = Sunna.set_free_time(ctx.id, "12:00", ctx.andrew)
    :ok = Sunna.tick(ctx.id)
    flush()
  end

  test "the work line is a brake: a spent cap ends the run and holds the line, saying so", ctx do
    key = started(ctx)
    :ok = Nisaba.set_budget(ctx.id, :work, 1, :day, ctx.andrew)

    assert {:error, %{kind: :brain_budget_stopped}} =
             WorkLoop.activity_turn(ctx.id, key, ctx.h, ctx.n, ctx.act, 1)

    assert %{running_act: nil} = Sunna.work_queue(ctx.id)
    assert {:rested, "holding: the work line is spent" <> _} = WorkLoop.check(ctx.id)
  end

  test "care first: a turn is put off while free time is underway", ctx do
    key = started(ctx)
    free_time_now(ctx)

    assert {:snooze, _} = WorkLoop.activity_turn(ctx.id, key, ctx.h, ctx.n, ctx.act, 1)
    refute_received {:asked, _}
  end

  # sunna#75, #96: the line waiting on care says why, and a pass whose
  # conversation has gone quiet holds nothing.
  test "care first: the line says why it waits, and goes once the pass is quiet", ctx do
    free_time_now(ctx)
    assert :care = WorkLoop.check(ctx.id)
    assert %{rested: "waiting: a free-time pass is underway" <> _} = Sunna.work_queue(ctx.id)

    Clock.Fake.advance(16 * 60)
    act = ctx.act
    assert {:started, ^act} = WorkLoop.check(ctx.id)
  end

  # sunna#76: he lets work go ahead of a free-time pass; she cannot.
  test "the witness skips the free-time wait with a note, and work starts; hers is refused",
       ctx do
    free_time_now(ctx)
    assert :care = WorkLoop.check(ctx.id)

    assert {:error, %{kind: :sunna_work_not_a_party}} =
             Sunna.work_skip_care(ctx.id, "mine first", ctx.me)

    Clock.Fake.advance(1)
    assert :ok = Sunna.work_skip_care(ctx.id, "the doc is due", ctx.andrew)
    assert %{rested: nil} = Sunna.work_queue(ctx.id)
    act = ctx.act
    assert {:started, ^act} = WorkLoop.check(ctx.id)
  end

  # sunna#77: quiet hours guard wakes that want him, not the line.
  test "quiet hours do not hold the work line; a check-in inside them still defers", ctx do
    # The suite's clock is 12:00 in her zone: quiet from 11:00 to 13:30.
    :ok = Sunna.set_quiet_hours(ctx.id, "11:00", "13:30", ctx.andrew)
    {:ok, checkin} = Sunna.set_checkin(ctx.id, nil, "noon", "12:01", ctx.andrew)

    key = started(ctx)
    assert :ok = WorkLoop.activity_turn(ctx.id, key, ctx.h, ctx.n, ctx.act, 1)
    assert_received {:asked, _}

    Clock.Fake.advance(60)
    assert :ok = Sunna.tick(ctx.id)
    assert %{firings: [%{key: ^checkin, outcome: "deferred"}]} = Sunna.today(ctx.id)
  end

  # brain#61: a stop ends the run unwrapped and rests the line; his
  # give-back or his skip lifts the rest.
  test "a run she stops with her safe word ends unwrapped, and the line rests until he lifts it",
       ctx do
    key = started(ctx)
    clear_jobs()

    Fake.script(fn _ -> {:ok, "Too much. OUROBOROS"} end, for: ctx.id)
    assert :ok = WorkLoop.activity_turn(ctx.id, key, ctx.h, ctx.n, ctx.act, 1)

    assert [] = jobs(ctx.id)
    assert %{running_act: nil, rested: "stopped: " <> _} = Sunna.work_queue(ctx.id)
    assert :stopped = WorkLoop.check(ctx.id)
    refute WorkLoop.due?(ctx.id)

    :ok = Sunna.work_reset_runs(ctx.id, "go on when you're ready", ctx.andrew)
    act = ctx.act
    assert {:started, ^act} = WorkLoop.check(ctx.id)
  end

  # sunna#37, #41: a run whose end was never recorded; the tick asks
  # about it, and the check ends it past the bound.
  test "a run left past the stale bound is asked about by the tick and ended, then runs again",
       ctx do
    _key = started(ctx)
    assert :running = WorkLoop.check(ctx.id)

    clear_jobs()
    :ok = Sunna.tick(ctx.id)
    refute Enum.any?(jobs(ctx.id), &(&1.args["turn"] == "check"))

    # Its turn's job still waits, so only the stale bound ends it.
    WorkWorker.enqueue_check(ctx.id, 3600)
    Clock.Fake.advance(181 * 60)
    :ok = Sunna.tick(ctx.id)
    assert WorkLoop.due?(ctx.id)
    assert :stalled = WorkLoop.check(ctx.id)

    act = ctx.act
    assert {:started, ^act} = WorkLoop.check(ctx.id)
  end

  # sunna#70: a restart killed the run's only job.
  test "a run with no job left is ended by the next check past a short grace", ctx do
    _key = started(ctx)
    Clock.Fake.advance(60)
    clear_jobs()
    assert :running = WorkLoop.check(ctx.id)

    Clock.Fake.advance(120)
    assert WorkLoop.due?(ctx.id)
    assert :stalled = WorkLoop.check(ctx.id)
  end

  test "the tick asks for a check when an activity of hers is ready and nothing runs", ctx do
    clear_jobs()
    :ok = Sunna.tick(ctx.id)
    assert Enum.any?(jobs(ctx.id), &(&1.args["turn"] == "check"))
  end

  # sunna#52: one broken run cannot spend the day.
  test "a run that fails waits before the next check", ctx do
    key = started(ctx)
    :ok = Nisaba.set_budget(ctx.id, :work, 1, :day, ctx.andrew)
    clear_jobs()

    assert {:error, _} = WorkLoop.activity_turn(ctx.id, key, ctx.h, ctx.n, ctx.act, 1)
    assert [%{args: %{"turn" => "check"}, at: at}] = jobs(ctx.id)
    wait = Oneiroi.Config.fetch!(:sunna, :work_retry_seconds)
    assert DateTime.diff(at, DateTime.utc_now()) > wait - 60
  end

  # sunna#53: the witness's, with a note; the loop checks at once.
  test "the witness gives the runs back with a note; she cannot", ctx do
    _key = started(ctx)
    assert %{runs_today: 1} = Sunna.work_queue(ctx.id)

    assert {:error, %{kind: :sunna_work_not_a_party}} =
             Sunna.work_reset_runs(ctx.id, "mine back", ctx.me)

    clear_jobs()
    assert :ok = Sunna.work_reset_runs(ctx.id, "the broken runs are fixed", ctx.andrew)
    assert %{runs_today: 0} = Sunna.work_queue(ctx.id)
    assert Enum.any?(jobs(ctx.id), &(&1.args["turn"] == "check"))
  end

  # sunna#67: a turn past the wait is still hers, in this run.
  test "a turn past the wait is the run going on in its conversation, never a new run", ctx do
    key = started(ctx)
    clear_jobs()

    store = {Oneiroi.Config, :values}
    values = :persistent_term.get(store)
    on_exit(fn -> :persistent_term.put(store, values) end)
    :persistent_term.put(store, Map.put(values, {:sunna, :wake}, Outlasted))

    assert :ok = WorkLoop.activity_turn(ctx.id, key, ctx.h, ctx.n, ctx.act, 1)
    act = ctx.act
    assert %{running_act: ^act} = Sunna.work_queue(ctx.id)
    assert [%{args: %{"session_key" => ^key, "turn" => 2}}] = jobs(ctx.id)

    assert :running = WorkLoop.check(ctx.id)
    assert [_one] = Enum.filter(Kumbukumbu.sessions({:resident, ctx.id}), &(&1.kind == "work"))

    # A closing turn past the wait ends the run, and the next check waits.
    clear_jobs()
    assert :ok = WorkLoop.activity_wrap(ctx.id, key, ctx.h, ctx.n, ctx.act)
    assert %{running_act: nil} = Sunna.work_queue(ctx.id)
    assert [%{args: %{"turn" => "check"}, at: at}] = jobs(ctx.id)
    wait = Oneiroi.Config.fetch!(:sunna, :work_retry_seconds)
    assert DateTime.diff(at, DateTime.utc_now()) > wait - 60
  end

  test "a turn left from an earlier run of the same activity does nothing in the new run", ctx do
    old = started(ctx)
    Clock.Fake.advance(60)
    clear_jobs()
    Clock.Fake.advance(120)
    assert :stalled = WorkLoop.check(ctx.id)
    act = ctx.act
    assert {:started, ^act} = WorkLoop.check(ctx.id)
    flush()

    assert :ok = WorkLoop.activity_turn(ctx.id, old, ctx.h, ctx.n, ctx.act, 2)
    refute_received {:asked, _}
    assert :ok = WorkLoop.activity_wrap(ctx.id, old, ctx.h, ctx.n, ctx.act)
    assert %{running_act: ^act} = Sunna.work_queue(ctx.id)
  end

  test "work_list reads her line: what runs or why it rests, and its runs", ctx do
    turn = %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.me}
    assert Tools.run("work_list", "{}", turn) =~ "Your line has not run yet. Runs today: 0 of"

    _key = started(ctx)
    text = Tools.run("work_list", "{}", turn)
    assert text =~ "Your line is running activity #{ctx.act} of task ##{ctx.n}."
    assert text =~ "Runs today: 1 of 1000. Since each last moved: #{ctx.act} 1 of 20."
  end
end
