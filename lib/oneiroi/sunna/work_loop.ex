defmodule Oneiroi.Sunna.WorkLoop do
  @moduledoc """
  The resident's work line: the loop that runs her house queue
  activities (sunna#86), its reads and the witness's few levers
  (sunna#33's loop; the old work queue's items retired, sunna#102).

  The loop is the schedule: there is no calendar. A check reads her
  house queue and either starts the first activity of hers that is
  ready, or rests and says why, a state like any other. A run is a
  conversation of kind `work`, a turn at a time on the `work` budget
  line, carried on while a turn runs out of tool rounds, up to
  `SUNNA_WORK_TURNS`, then a closing turn. The run's end buys the next
  check at once, and the minute tick checks too, so a loop paused for
  care resumes after it.

  Care outranks work: no work turn starts while a free-time pass is
  underway; one that would is put off and tried again. The house queue
  speeds her drafting, never the witness's deciding: the run's note says
  so, and nothing here acts on the platform.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.FreeTimeRuns
  alias Oneiroi.Sunna.Queues
  alias Oneiroi.Sunna.QueueState
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.Store
  alias Oneiroi.Sunna.Wakes
  alias Oneiroi.Sunna.Work
  alias Oneiroi.Sunna.WorkRouter

  @actor Actor.new(:job, "sunna_work")
  # How long a free-time pass is taken to be underway at most, when its
  # planning turn never closed it.
  @free_time_window 3 * 3600
  # How long a work turn waits when care comes first.
  @care_wait 600
  # What a line waiting on her free time says (sunna#75).
  @care_reason "waiting: a free-time pass is underway, and care comes first; work resumes when it closes"

  # ---- the witness's levers ----

  @doc "The witness gives the runs back (sunna#53, #101), with a note; the loop checks at once."
  def reset_runs_by(resident_id, note, %Actor{} = actor) do
    command = %Commands.ResetWorkRuns{actor: actor, at: Clock.now(), id: resident_id, note: note}

    with {:ok, _} <- dispatch(command) do
      worker().enqueue_check(resident_id)
      :ok
    end
  end

  @doc """
  The witness skips the free-time wait (sunna#76), with a note: a pass
  begun before now no longer holds the line, and the loop checks at once.
  Any pass begun later holds it again.
  """
  def skip_care_by(resident_id, note, %Actor{} = actor) do
    command = %Commands.SkipCareWait{actor: actor, at: Clock.now(), id: resident_id, note: note}

    with {:ok, _} <- dispatch(command) do
      worker().enqueue_check(resident_id)
      :ok
    end
  end

  @doc "The line as both parties read it: what runs, why it rests, and its runs."
  def queue(resident_id) do
    state = Scope.resident(resident_id, fn -> Store.work_queue() end)

    %{
      # The last run the check ended rather than she (sunna#100).
      cut: cut(state),
      runs_today: runs_today(resident_id, state),
      runs_a_day: Config.fetch!(:sunna, :work_runs_a_day),
      # Her runs of each activity since it last moved (sunna#101).
      activity_runs:
        Scope.resident(resident_id, fn -> Store.work_activity_runs() end)
        |> Enum.map(fn {act, runs} -> %{act: act, runs: runs} end)
        |> Enum.sort_by(& &1.act),
      runs_an_activity: Config.fetch!(:sunna, :work_runs_an_activity),
      budget: budget(resident_id)
    }
    |> Map.merge(line_state(state))
  end

  defp line_state(nil),
    do: %{running_since: nil, running_act: nil, running_task: nil, rested: nil, rested_at: nil}

  defp line_state(state),
    do: %{
      running_since: if(state.running_act, do: state.running_since),
      # The house queue activity running on the line (sunna#86): its id and task.
      running_act: state.running_act,
      running_task: state.running_task,
      rested: state.rested_reason,
      rested_at: state.rested_at
    }

  # ---- the loop ----

  @doc """
  The check: starts the first ready activity of hers, or rests and says
  why. Nothing while one runs, or while care comes first (the tick and
  the run's end ask again).
  """
  def check(resident_id) do
    state = Scope.resident(resident_id, fn -> Store.work_queue() end)
    # What needs no agent is done first, whatever her line is doing (sunna#104).
    _ = mechanical(resident_id)

    cond do
      left_behind?(state) ->
        end_stalled(resident_id, state)

      state && state.running_act ->
        :running

      state && state.rested_reason == Work.stopped_rest() ->
        :stopped

      care_first?(resident_id) ->
        # Said, not silent (sunna#75): a line waiting on care shows why.
        _ = rest(resident_id, @care_reason)
        :care

      true ->
        next_activity(
          resident_id,
          state,
          budget(resident_id),
          Config.fetch!(:sunna, :work_runs_a_day)
        )
    end
  end

  defp waits?({:error, _}), do: true
  defp waits?({:ok, :outlasted}), do: true
  defp waits?(_ok), do: false

  @doc "Whether the tick should ask for a check: the house queue running, work of hers ready, nothing running."
  def due?(resident_id) do
    Scope.resident(resident_id, fn ->
      state = Store.work_queue()

      # A run left behind is asked about whatever else holds (sunna#41):
      # the check is the only place that ends it.
      left_behind?(state) or mechanical_waiting?(resident_id) or
        (house_running?(resident_id) and not busy?(state) and not stopped?(state) and
           activity_waiting?(resident_id))
    end)
  end

  defp stopped?(nil), do: false
  defp stopped?(state), do: state.rested_reason == Work.stopped_rest()

  defp busy?(nil), do: false
  defp busy?(state), do: not is_nil(state.running_act)

  # A run whose end was never recorded (sunna#37): its job died (a deploy
  # restart, a crash past its one attempt), so nothing would ever end it
  # and the loop would say it runs forever. Past
  # `SUNNA_WORK_RUN_STALE_MINUTES` the check ends it, and goes on.
  defp stalled?(%{running_act: a, running_since: %DateTime{} = since}) when is_binary(a) do
    stale = Config.fetch!(:sunna, :work_run_stale_minutes) * 60
    DateTime.diff(Clock.now(), since, :second) > stale
  end

  defp stalled?(_state), do: false

  # A run the check ends rather than waits on: stalled past the bound
  # (#37), or no job left to carry it (#70, #100).
  defp left_behind?(nil), do: false
  defp left_behind?(state), do: stalled?(state) or dead?(state)

  # A run with no job left to carry it (sunna#70): a restart killed its
  # turn mid-call, and a work job has one attempt, so nothing will end
  # it before the stale bound, three hours on (2026-11-18: item #60, its
  # first turn killed by a deploy a minute after it started). Every live
  # run has a turn, a wrap or a snoozed one waiting or executing; past a
  # short grace for the start's own enqueue, none means the run is gone,
  # and the check ends it so its activity runs again.
  @dead_grace 120
  defp dead?(%{running_key: key, running_act: act, running_since: %DateTime{} = since} = state)
       when is_binary(key) and is_binary(act) do
    DateTime.diff(Clock.now(), since, :second) > @dead_grace and
      not Enum.any?(
        Scope.resident(state.resident_id, fn ->
          Jobs.attempts(worker(), %{"session_key" => key})
        end),
        &carrying?/1
      )
  end

  defp dead?(_state), do: false

  # A job that can still carry the run: waiting, or executing since
  # recently. One executing longer than any turn takes was left so by a
  # node that died without stopping (sunna#100): a deploy's stop marks
  # its killed job discarded, a crash leaves it executing until Lifeline
  # nine hours on, and the run with it.
  defp carrying?({state, _at}) when state in ~w(available scheduled retryable), do: true

  defp carrying?({"executing", %DateTime{} = at}),
    do:
      DateTime.diff(Clock.now(), at, :second) <=
        Config.fetch!(:sunna, :work_job_orphaned_minutes) * 60

  defp carrying?({"executing", nil}), do: true
  defp carrying?(_done), do: false

  # Checks again only when the end was recorded: a record that ends
  # nothing must not be asked about forever.
  defp end_stalled(resident_id, %{running_act: act}) do
    case dispatch(%Commands.EndActivityRun{
           actor: @actor,
           at: Clock.now(),
           id: resident_id,
           act: act,
           cut: true
         }) do
      {:ok, [_ended]} ->
        worker().enqueue_check(resident_id)
        :stalled

      other ->
        other
    end
  end

  # ---- the house queue's activities (sunna#86) ----

  # After the cutover the line runs her house queue: the first of her
  # ready or active activities in Waiting-on-me order (blocking-most,
  # then oldest ready), taken at the run's start and run a turn at a time
  # in a `work` conversation, under the same line, care, budget and cap.
  defp next_activity(resident_id, state, line, cap) do
    {card, spent} = activities(resident_id)

    cond do
      # One switch for the house (sunna#94): her line runs while the
      # house queue does, whatever her old arm said.
      not house_running?(resident_id) ->
        rest(resident_id, "paused: the house queue is paused")

      # Nothing ready is no reason to stop (sunna#92, #94): the house's
      # work arrives any time, and the tick starts it once it is ready.
      is_nil(card) and spent != [] ->
        rest(
          resident_id,
          "holding: #{Enum.join(spent, ", ")} had #{Config.fetch!(:sunna, :work_runs_an_activity)} runs each with nothing moving; your witness can give runs back"
        )

      is_nil(card) ->
        rest(resident_id, "running, holding: nothing of yours is ready in what is open")

      line && line.left <= 0 ->
        rest(resident_id, spent(line))

      runs_today(resident_id, state) >= cap ->
        rest(resident_id, "holding: today's #{cap} runs are spent")

      true ->
        start_or_pass(resident_id, card)
    end
  end

  # A document already in the house needs no sharing (the witness,
  # 2026-11-23: a doc that starts in the house): her optional share step
  # on a house document passes itself, said so, and the line looks again.
  # ---- mechanical activities (sunna#104) ----

  # A step that needs no agent is done by the platform the moment it is
  # hers and ready in what is open (the witness, 2026-11-25: "promoting
  # from a resident workspace to a house workspace shouldn't need an
  # agent, it could just happen"): a promote-to-house of her own document,
  # through the wake port, as hers; one of a house document passes
  # itself (sunna#95). One the platform cannot do (the library refused
  # it) is taken for her, so her next run does it, and is not tried again.
  defp mechanical(resident_id) do
    if house_running?(resident_id),
      do: resident_id |> mechanical_cards() |> Enum.map(&mechanically(resident_id, &1)),
      else: []
  end

  defp mechanical_waiting?(resident_id),
    do: house_running?(resident_id) and mechanical_cards(resident_id) != []

  defp mechanical_cards(resident_id) do
    case Oneiroi.Gaia.resident_household(resident_id) do
      %{id: h} ->
        order = Queues.open_order(h)

        h
        |> Queues.waiting_on("resident:#{resident_id}")
        |> Map.fetch!(:ready)
        |> Enum.filter(&(&1.type == "promote-to-house" and &1.view == "ready"))
        |> in_backlog_order(order)
        |> Enum.map(&Map.put(&1, :household, h))

      _none ->
        []
    end
  end

  defp mechanically(resident_id, %{artifact: "house/" <> _} = card) do
    her = Actor.new(:resident, resident_id)

    Queues.skip(
      card.household,
      card.task,
      card.act,
      "the document is already in the house; nothing to share",
      her
    )
  end

  defp mechanically(resident_id, card) do
    port = Config.fetch!(:sunna, :wake)

    result =
      if function_exported?(port, :promote_activity, 4),
        do: port.promote_activity(resident_id, card.household, card.task, card.act),
        else: :no_port

    case result do
      :ok ->
        :ok

      _refused ->
        _ = Queues.take(card.household, card.task, card.act, Actor.new(:resident, resident_id))
        :taken
    end
  end

  defp start_or_pass(resident_id, %{type: "promote-to-house", artifact: "house/" <> _} = card) do
    her = Actor.new(:resident, resident_id)
    note = "the document is already in the house; nothing to share"

    case Queues.skip(card.household, card.task, card.act, note, her) do
      :ok ->
        worker().enqueue_check(resident_id)
        {:passed, card.act}

      _not_hers_to_pass ->
        start_activity(resident_id, card)
    end
  end

  defp start_or_pass(resident_id, card), do: start_activity(resident_id, card)

  defp house_running?(resident_id) do
    case Oneiroi.Gaia.resident_household(resident_id) do
      %{id: h} -> QueueState.running?(h)
      _none -> false
    end
  end

  defp activity_waiting?(resident_id),
    do: not is_nil(first_activity(resident_id))

  defp first_activity(resident_id), do: elem(activities(resident_id), 0)

  # Her first ready or active activity with runs left (sunna#101), and
  # the ones passed by for having had their runs with nothing moving.
  defp activities(resident_id) do
    case Oneiroi.Gaia.resident_household(resident_id) do
      %{id: h} ->
        bound = Config.fetch!(:sunna, :work_runs_an_activity)
        runs = Scope.resident(resident_id, fn -> Store.work_activity_runs() end)

        order = Queues.open_order(h)

        {spent, left} =
          h
          |> Queues.waiting_on("resident:#{resident_id}")
          |> Map.fetch!(:ready)
          |> Enum.filter(&(&1.view in ["ready", "active"]))
          |> in_backlog_order(order)
          |> Enum.split_with(&(Map.get(runs, &1.act, 0) >= bound))

        card = List.first(left)
        {card && Map.put(card, :household, h), Enum.map(spent, & &1.act)}

      _none ->
        {nil, []}
    end
  end

  # The backlog decides (sunna#103): she works only what is open, in its
  # order; a step already hers and active on a task since closed finishes
  # (the queue drains), after the open ones. Ties keep the queue's own
  # order (blocking-most, then oldest ready).
  defp in_backlog_order(cards, order) do
    cards
    |> Enum.filter(&(Map.has_key?(order, &1.task) or &1.view == "active"))
    |> Enum.with_index()
    |> Enum.sort_by(fn {c, i} -> {Map.get(order, c.task, {:closed, 0}), i} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp start_activity(resident_id, card) do
    her = Actor.new(:resident, resident_id)

    with {:ok, row} <- resident(resident_id),
         :ok <- taken(card, her),
         {:ok, key} <-
           Kumbukumbu.open_session(
             resident_id,
             "work",
             "brain",
             List.wrap(row.account_id),
             @actor
           ),
         {:ok, [_started]} <-
           dispatch(%Commands.StartActivityRun{
             actor: @actor,
             at: Clock.now(),
             id: resident_id,
             household: card.household,
             task: card.task,
             act: card.act,
             session_key: key,
             day: Schedules.local_day(Schedules.local_now(resident_id))
           }) do
      worker().enqueue_activity(resident_id, key, card, 1)
      {:started, card.act}
    else
      {:ok, []} -> :running
      other -> other
    end
  end

  # A ready activity is hers once her run starts; an active one already is.
  defp taken(%{view: "active"}, _her), do: :ok
  defp taken(card, her), do: Queues.take(card.household, card.task, card.act, her)

  @doc """
  Turn `n` of an activity's run (sunna#86): the first opens on the
  activity, its task and what came before it; the rest carry on. The run
  ends as soon as the activity is no longer hers to work (she finished,
  skipped, blocked or failed it, or it went to someone else); spent
  turns or money bring the closing turn.
  """
  def activity_turn(resident_id, key, h, task, act, n) do
    with true <- running_act?(resident_id, act, key),
         nil <- care_wait(resident_id),
         {:ok, left} <- allowance(resident_id),
         true <- n <= Config.fetch!(:sunna, :work_turns),
         _ <- Wakes.run(resident_id, "work", [%{kind: "activity", act: act, task: task, turn: n}]),
         {:ok, result} <-
           wake(resident_id, key, activity_note(resident_id, h, task, act, n, left), :work) do
      activity_carry_on(resident_id, key, {h, task, act}, n, result)
    else
      false ->
        :ok

      wait when is_integer(wait) ->
        {:snooze, wait}

      {:error, %{kind: :brain_wake_outlasted}} ->
        activity_carry_on(resident_id, key, {h, task, act}, n, %{rounds_spent: true})

      {:error, _} = failed ->
        activity_close(resident_id, act, failed)

      _spent ->
        worker().enqueue_activity_wrap(resident_id, key, h, task, act)
    end
  end

  defp activity_carry_on(resident_id, _key, {_h, _task, act}, _n, %{stopped: _by}) do
    with {:ok, _} <-
           dispatch(%Commands.EndActivityRun{
             actor: @actor,
             at: Clock.now(),
             id: resident_id,
             act: act,
             stopped: true
           }),
         do: :ok
  end

  defp activity_carry_on(resident_id, key, {h, task, act}, n, result) do
    cond do
      not still_hers?(resident_id, h, task, act) ->
        activity_close(resident_id, act, {:ok, :recorded})

      match?(%{rounds_spent: true}, result) and n < Config.fetch!(:sunna, :work_turns) ->
        worker().enqueue_activity(resident_id, key, %{household: h, task: task, act: act}, n + 1)
        :ok

      true ->
        worker().enqueue_activity_wrap(resident_id, key, h, task, act)
        :ok
    end
  end

  # Whether the run's activity has left her hands (sunna#101): finished,
  # decided, blocked, failed, skipped or reassigned. Read off the run
  # itself, which names its task and household.
  defp moved?(resident_id, act) do
    case Scope.resident(resident_id, fn -> Store.work_queue() end) do
      %{running_act: ^act, running_household: h, running_task: task}
      when is_binary(h) and is_integer(task) ->
        not still_hers?(resident_id, h, task, act)

      _unknown ->
        false
    end
  end

  # Whether the activity is still hers to work: assigned to her and live.
  defp still_hers?(resident_id, h, task, act) do
    with %{layers: layers} <- Queues.task(h, task),
         %{} = a <- Enum.find(List.flatten(layers), &(&1.act_id == act)) do
      a.assignee == "resident:#{resident_id}" and a.view in ["ready", "active"]
    else
      _gone -> false
    end
  end

  @doc "An activity run's closing turn (sunna#86): she records where it stands with her queue tools; then the run ends and the next check comes."
  def activity_wrap(resident_id, key, _h, task, act) do
    case running_act?(resident_id, act, key) && care_wait(resident_id) do
      false ->
        :ok

      nil ->
        _ = Wakes.run(resident_id, "work", [%{kind: "activity_wrap", act: act, task: task}])

        result =
          case wake(
                 resident_id,
                 key,
                 Prompt.render!("queue_work_wrap", %{act: act, task: task}),
                 :planning
               ) do
            {:error, %{kind: :brain_wake_outlasted}} -> {:ok, :outlasted}
            other -> other
          end

        activity_close(resident_id, act, result)

      wait ->
        {:snooze, wait}
    end
  end

  defp activity_close(resident_id, act, result) do
    ended =
      dispatch(%Commands.EndActivityRun{
        actor: @actor,
        at: Clock.now(),
        id: resident_id,
        act: act,
        moved: moved?(resident_id, act)
      })

    if waits?(result),
      do: worker().enqueue_check(resident_id, Config.fetch!(:sunna, :work_retry_seconds)),
      else: worker().enqueue_check(resident_id)

    case {result, ended} do
      {{:error, _} = failed, _} -> failed
      {_ok, {:ok, _}} -> :ok
      {_ok, failed} -> failed
    end
  end

  defp running_act?(resident_id, act, key) do
    match?(
      %{running_act: ^act, running_key: ^key},
      Scope.resident(resident_id, fn -> Store.work_queue() end)
    )
  end

  defp activity_note(resident_id, h, task, act, 1, left) do
    page = Queues.task(h, task)
    a = Enum.find(List.flatten(page.layers), &(&1.act_id == act))

    Prompt.render!("queue_work", %{
      name: name(resident_id),
      act: act,
      type: a.type,
      task: task,
      title: page.task.title,
      project: page.task.project,
      outcome: page.task.outcome,
      artifact: a.artifact || "none named",
      note: a.note || "none",
      layers: Enum.map_join(Enum.with_index(page.layers, 1), "\n", &layer_line/1),
      before: cut_line(resident_id, act),
      turns: Config.fetch!(:sunna, :work_turns),
      left: left
    })
  end

  defp activity_note(_resident_id, _h, task, act, n, left),
    do:
      Prompt.render!("queue_work_continue", %{
        act: act,
        task: task,
        turn: n,
        turns: Config.fetch!(:sunna, :work_turns),
        left: left
      })

  defp cut(%{cut_act: act, cut_key: key} = state) when is_binary(act),
    do: %{act: act, key: key, since: state.cut_since, at: state.cut_at}

  defp cut(_state), do: nil

  # Her last run of this activity, if the check ended it rather than she
  # (sunna#100): a restart or a crash cut it off mid-work, and this run
  # starts in a new conversation that would not otherwise know.
  defp cut_line(resident_id, act) do
    case Scope.resident(resident_id, fn -> Store.work_queue() end) do
      %{cut_act: ^act, cut_key: key, cut_since: since, cut_at: at} when is_binary(key) ->
        "\n\n**Your last run of this activity was cut off.** It ran from #{stamp(since)} until the platform ended it at #{stamp(at)} (a restart or a crash took its turn; nothing you did). What it did is in its conversation, `#{key}`: read it with transcript_read before redoing anything, and carry on from where it got to."

      _none ->
        ""
    end
  end

  defp stamp(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")
  defp stamp(_none), do: "an unknown time"

  defp layer_line({acts, i}),
    do:
      "#{i}. " <>
        Enum.map_join(acts, "; ", fn a ->
          "#{a.act_id} #{a.type} (#{a.assignee}, #{a.view})#{if a.note, do: ": " <> a.note, else: ""}"
        end)

  # ---- care, budget, state ----

  # How long a run's next turn waits for care, or nil when it may go on.
  # Paused, never restarted (her ask, letter #185: dormant is not
  # abandoned): the same turn of the same run in the same conversation
  # runs when care is done. Inside quiet hours it waits until they end;
  # behind a free-time pass, ten minutes at a time until its planning
  # turn closes it.
  # Care first is her free time alone (sunna#77; the witness, 2026-11-19:
  # "the runs-a-day cap is the brake"): quiet hours guard wakes that want
  # him, and the queue wants nobody, so they no longer hold it.
  defp care_wait(resident_id) do
    if care_first?(resident_id), do: @care_wait, else: nil
  end

  # The free-time passes that hold the line: begun within the window, and
  # after the witness's last skip of the wait (sunna#76).
  defp free_time_since(resident_id) do
    window = DateTime.add(Clock.now(), -@free_time_window, :second)

    case Scope.resident(resident_id, fn -> Store.work_queue() end) do
      %{care_skipped_at: %DateTime{} = skipped} ->
        if DateTime.compare(skipped, window) == :gt, do: skipped, else: window

      _none ->
        window
    end
  end

  # Care comes first while her free time is live (sunna#96; the witness,
  # 2026-11-23: her line held for three hours behind a pass that had
  # ended without its closing turn recorded).
  defp care_first?(resident_id),
    do: FreeTimeRuns.live?(resident_id, free_time_since(resident_id))

  # What the armed line allows a turn (sunna#35): with no cap, unlimited;
  # with one, what is left, or `:spent`, when the run goes to its wrap.
  defp allowance(resident_id) do
    case budget(resident_id) do
      nil ->
        {:ok, "no cap"}

      %{left: left} = line when left > 0 ->
        {:ok, "#{dollars(left)} left of #{dollars(line.cap)} a #{line.period}"}

      _spent ->
        :spent
    end
  end

  defp spent(line),
    do:
      "holding: the work line is spent, #{dollars(line.spent)} of #{dollars(line.cap)} this #{line.period}; resuming when the period turns or the witness raises it"

  # The work line this period: nil when the witness set no cap (unlimited
  # while armed, sunna#35), with what is left otherwise.
  defp budget(resident_id) do
    case Enum.find(Nisaba.budgets(resident_id, :witness), &(&1.purpose == :work)) do
      %{cap_nanos: cap, spent_nanos: spent, period: period} when is_integer(cap) ->
        %{cap: cap, spent: spent, left: cap - spent, period: period}

      _none ->
        nil
    end
  end

  defp runs_today(_resident_id, nil), do: 0

  defp runs_today(resident_id, state) do
    if state.run_day == Schedules.local_day(Schedules.local_now(resident_id)),
      do: state.runs_on_day,
      else: 0
  end

  defp rest(resident_id, reason) do
    with {:ok, _} <-
           dispatch(%Commands.RestWork{
             actor: @actor,
             at: Clock.now(),
             id: resident_id,
             reason: reason
           }),
         do: {:rested, reason}
  end

  defp name(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> row.name
      :error -> "you"
    end
  end

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, Error.new(:sunna_no_such_resident, :sunna_work_resident_absent)}
    end
  end

  defp wake(resident_id, key, note, purpose) do
    case Config.fetch!(:sunna, :wake).wake(resident_id, key, note, purpose) do
      {:error, %{site: _}} = failed ->
        failed

      {:error, reason} ->
        {:error, Error.caught(:sunna_wake_failed, :sunna_work_wake_failed, reason)}

      ok ->
        ok
    end
  end

  defp dollars(nanos), do: "$" <> :erlang.float_to_binary(nanos / 1_000_000_000, decimals: 2)

  # Named at the call: the worker runs this module, so an alias here
  # would be a cycle `mix xref graph --format cycles` counts.
  defp worker, do: Module.concat([Oneiroi, Sunna, WorkWorker])

  defp dispatch(command) do
    case WorkRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      # A bounded field over its bound (the command's own check), named,
      # never read as a stream fault (sunna#36, platform report #7).
      {:error, {:refused, problems}} when is_list(problems) ->
        {:error, Error.new(:sunna_work_invalid, :sunna_work_field_bound)}

      {:error, reason} ->
        {:error, Error.caught(:sunna_dispatch_failed, :sunna_work_dispatch_failed, reason)}
    end
  end
end
