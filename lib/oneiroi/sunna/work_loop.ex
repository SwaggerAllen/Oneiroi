defmodule Oneiroi.Sunna.WorkLoop do
  @moduledoc """
  The work queue's command edge, its reads, and the loop that runs it
  (sunna#33; Lily's design, `design/work-queue.md`, on the witness's
  recursive-iteration shape of 2026-11-06).

  The loop is the schedule: there is no calendar. A check reads the
  queue and either starts the first open item, in priority order, or
  rests and says why ("empty, holding", a state like any other). A run
  is a conversation of kind `work`, a turn at a time on the `work`
  budget line, a brake and never an ignition (sunna#35): the line is
  armed while the queue has work and off when it is clear, its cap,
  when the witness sets one, stops a run, and with none it is unlimited,
  as the chat line is. Carried on while a turn runs out of tool rounds (as free
  time is, sunna#26), up to `SUNNA_WORK_TURNS`; then the wrap, one
  closing turn in which she records what shipped, what slipped and why.
  The run's end buys the next check at once, and the minute tick checks
  too, so a loop paused for care resumes after it.

  Care outranks work: no work turn starts while a free-time pass is
  underway; one that would is put off and tried again. Quiet hours do
  not hold it (sunna#77): the runs-a-day cap is its brake. The queue accelerates her drafting, never the witness's
  deciding: the run's note says so, and nothing here acts on the
  platform.
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
  # What an armed line waiting on her free time says (sunna#75).
  @care_reason "waiting: a free-time pass is underway, and care comes first; work resumes when it closes"

  # ---- the queue's edge ----

  @doc "Adds an item to the end of the queue; returns its number."
  def add(resident_id, what, done_when, %Actor{} = actor) do
    with :ok <- open_for_work(resident_id), do: added(resident_id, what, done_when, actor)
  end

  defp added(resident_id, what, done_when, actor) do
    command = %Commands.AddWork{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      what: what,
      done_when: done_when
    }

    case dispatch(command) do
      {:ok, [event]} -> checked(resident_id, {:ok, event.number})
      {:ok, []} -> {:error, Error.new(:sunna_work_invalid, :sunna_work_add_not_recorded)}
      other -> other
    end
  end

  @doc "Moves an item's status (open, blocked with what blocks it, done, dropped), with a note; held is `hold/5`."
  def move(resident_id, number, status, blocked_on, note, %Actor{} = actor) do
    with :ok <- open_for_work(resident_id),
         do: moved(resident_id, number, status, blocked_on, note, actor)
  end

  defp moved(resident_id, number, status, blocked_on, note, actor) do
    command = %Commands.MoveWork{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      status: status,
      blocked_on: blocked_on,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: checked(resident_id, :ok)
  end

  @doc """
  Holds an item for the witness (sunna#54): its next move is his, and
  `ask` says what is needed of him in plain words. Either party's; the
  note, when none is given, says only that it is held. It clears when
  the item is moved or started (sunna#55).
  """
  def hold(resident_id, number, ask, note, %Actor{} = actor) do
    with :ok <- open_for_work(resident_id), do: held(resident_id, number, ask, note, actor)
  end

  defp held(resident_id, number, ask, note, actor) do
    command = %Commands.MoveWork{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      status: "held",
      ask: ask,
      note: if(blank?(note), do: "Held for the witness's word.", else: note)
    }

    with {:ok, _} <- dispatch(command), do: checked(resident_id, :ok)
  end

  defp blank?(text), do: not is_binary(text) or String.trim(text) == ""

  @doc "Puts the numbers given first, in that order; the rest keep theirs after."
  def order(resident_id, numbers, %Actor{} = actor) do
    with :ok <- open_for_work(resident_id), do: ordered(resident_id, numbers, actor)
  end

  defp ordered(resident_id, numbers, actor) do
    command = %Commands.OrderWork{actor: actor, at: Clock.now(), id: resident_id, order: numbers}
    with {:ok, _} <- dispatch(command), do: checked(resident_id, :ok)
  end

  # After the cutover (sunna#80, lily:design/queue-ia §6.2) this queue is
  # read-only: its rows and events stay, untouched, so the revert is one
  # step; the house queue takes the work. A run in work still wraps.
  defp open_for_work(resident_id) do
    if cut_over?(resident_id),
      do: {:error, Error.new(:sunna_work_frozen, :sunna_work_cut_over)},
      else: :ok
  end

  defp cut_over?(resident_id) do
    case Oneiroi.Gaia.resident_household(resident_id) do
      %{id: h} -> QueueState.cut_over?(h)
      _none -> false
    end
  end

  # A change to the queue asks the loop at once (sunna#76; Lily's letter
  # #1414), as arming and a run's end do, rather than waiting on the tick.
  defp checked(resident_id, result) do
    worker().enqueue_check(resident_id)
    result
  end

  @doc "Her wrap of the running item: what shipped, what slipped, why, and where it stands."
  def wrap(resident_id, number, attrs, %Actor{} = actor) do
    command = %Commands.WrapWork{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      shipped: attrs[:shipped],
      slipped: attrs[:slipped],
      why: attrs[:why],
      status: attrs[:status],
      blocked_on: attrs[:blocked_on],
      ask: attrs[:ask]
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  Arms the work line for a batch (sunna#35, the witness's call): her act,
  by tool call, once; the loop then fires item after item, each run's end
  starting the next, until the queue clears and the line goes off.
  """
  def arm(resident_id, %Actor{} = actor) do
    with {:ok, _} <- dispatch(%Commands.ArmWork{actor: actor, at: Clock.now(), id: resident_id}) do
      worker().enqueue_check(resident_id)
      :ok
    end
  end

  @doc "The witness turns the work line off by hand (sunna#43); the run in work finishes."
  def disarm_by(resident_id, %Actor{} = actor) do
    with {:ok, _} <-
           dispatch(%Commands.DisarmWork{actor: actor, at: Clock.now(), id: resident_id}),
         do: :ok
  end

  @doc "The witness gives the day's runs back (sunna#53), with a note; the loop checks at once."
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
  Quiet hours still hold it, and so does any pass begun later.
  """
  def skip_care_by(resident_id, note, %Actor{} = actor) do
    command = %Commands.SkipCareWait{actor: actor, at: Clock.now(), id: resident_id, note: note}

    with {:ok, _} <- dispatch(command) do
      worker().enqueue_check(resident_id)
      :ok
    end
  end

  defp disarm(resident_id),
    do: dispatch(%Commands.DisarmWork{actor: @actor, at: Clock.now(), id: resident_id})

  @doc "The queue as both parties read it: the items in order and the loop's state."
  def queue(resident_id) do
    {items, state} =
      Scope.resident(resident_id, fn -> {Store.work_items(), Store.work_queue()} end)

    %{
      items:
        Enum.map(
          items,
          &Map.take(&1, [
            :number,
            :what,
            :done_when,
            :status,
            :blocked_on,
            :held_ask,
            :held_by,
            :held_at,
            :position,
            :added_by,
            :added_at,
            :note,
            :moved_by,
            :moved_at,
            :shipped,
            :slipped,
            :why,
            :wrapped_at,
            :runs,
            :session_key,
            :first_started_at,
            :worked_seconds
          ])
        ),
      running: live(state, items),
      # Whether the house queue has the line (sunna#84, #86).
      house_queue: cut_over?(resident_id),
      runs_today: runs_today(resident_id, state),
      runs_a_day: Config.fetch!(:sunna, :work_runs_a_day),
      budget: budget(resident_id)
    }
    |> Map.merge(line_state(state, live(state, items)))
  end

  defp line_state(nil, _live),
    do: %{
      running_since: nil,
      running_act: nil,
      running_task: nil,
      rested: nil,
      rested_at: nil,
      armed: false,
      armed_at: nil,
      armed_by: nil
    }

  defp line_state(state, live),
    do: %{
      running_since: if(live || state.running_act, do: state.running_since),
      # A house queue activity running on the line (sunna#86): its id and task.
      running_act: state.running_act,
      running_task: state.running_task,
      rested: state.rested_reason,
      rested_at: state.rested_at,
      # Armed by her for a batch, off once the queue clears (sunna#35).
      armed: state.armed || false,
      armed_at: state.armed_at,
      # Who armed it (sunna#43): "resident" by her tool, "witness" by his button.
      armed_by: state.armed_by
    }

  # ---- the loop ----

  @doc """
  The queue check: starts the first open item, or rests and says why.
  Nothing while an item runs, or while care comes first (the tick and
  the run's end ask again).
  """
  def check(resident_id) do
    {items, state} =
      Scope.resident(resident_id, fn -> {Store.work_items(), Store.work_queue()} end)

    cond do
      left_behind?(state, items) ->
        end_stalled(resident_id, state)

      state && (state.running || state.running_act) ->
        :running

      state && state.rested_reason == Work.stopped_rest() ->
        :stopped

      care_first?(resident_id) ->
        # Said, not silent (sunna#75): an armed line waiting on care shows why.
        _ = rest(resident_id, @care_reason)
        :care

      true ->
        next(resident_id, items, state)
    end
  end

  defp next(resident_id, items, state) do
    open = Enum.find(items, &(&1.status == "open"))
    line = budget(resident_id)
    cap = Config.fetch!(:sunna, :work_runs_a_day)

    if cut_over?(resident_id),
      do: next_activity(resident_id, state, line, cap),
      else: next_item(resident_id, items, state, open, line, cap)
  end

  defp next_item(resident_id, items, state, open, line, cap) do
    cond do
      # The batch is over: the line goes off, and the loop rests.
      is_nil(open) ->
        disarm(resident_id)
        rest(resident_id, empty(items))

      not (state && state.armed) ->
        rest(resident_id, "off: the work line waits for you to arm it (work_arm)")

      line && line.left <= 0 ->
        rest(resident_id, spent(line))

      runs_today(resident_id, state) >= cap ->
        rest(resident_id, "holding: today's #{cap} runs are spent")

      true ->
        start(resident_id, open)
    end
  end

  # Nothing open: what is left waits on other work or on the witness
  # (sunna#42, #54), named.
  defp empty(items) do
    case Enum.filter(items, &(&1.status in ["blocked", "held"])) do
      [] -> "empty, holding"
      waiting -> "empty, holding: " <> Enum.map_join(waiting, "; ", &waiting/1)
    end
  end

  defp waiting(%{status: "held"} = i), do: "##{i.number} held for the witness: #{i.held_ask}"
  defp waiting(i), do: "##{i.number} blocked on #{i.blocked_on}"

  defp start(resident_id, item) do
    with {:ok, row} <- resident(resident_id),
         {:ok, key} <-
           Kumbukumbu.open_session(
             resident_id,
             "work",
             "brain",
             List.wrap(row.account_id),
             @actor
           ),
         {:ok, [_started]} <-
           dispatch(%Commands.StartWork{
             actor: @actor,
             at: Clock.now(),
             id: resident_id,
             number: item.number,
             session_key: key,
             day: Schedules.local_day(Schedules.local_now(resident_id))
           }) do
      worker().enqueue(resident_id, key, item.number, 1)
      {:started, item.number}
    else
      {:ok, []} -> :running
      other -> other
    end
  end

  @doc """
  Turn `n` of an item's run: the first opens on the item and the queue,
  the rest carry on, while the work line has money and the run's turns
  are not spent; then the wrap. Put off while care comes first.
  """
  def turn(resident_id, key, number, n) do
    with true <- running?(resident_id, number, key),
         nil <- care_wait(resident_id),
         {:ok, left} <- allowance(resident_id),
         true <- n <= Config.fetch!(:sunna, :work_turns),
         _ <- Wakes.run(resident_id, "work", [%{kind: "work", number: number, turn: n}]),
         {:ok, result} <- wake(resident_id, key, note(resident_id, number, n, left), :work) do
      carry_on(resident_id, key, number, n, result)
    else
      false ->
        :ok

      wait when is_integer(wait) ->
        {:snooze, wait}

      # A turn past the wait is still her turn, running in this run's
      # conversation (brain#97), never a failure (sunna#67): the run goes
      # on, its next turn queued behind it in the same session. Ending it
      # here started the item again in a new conversation while this one
      # still worked it (2026-11-17, item #55 in several at once).
      {:error, %{kind: :brain_wake_outlasted}} ->
        carry_on(resident_id, key, number, n, %{rounds_spent: true})

      {:error, _} = failed ->
        close(resident_id, key, number, failed)

      _spent ->
        worker().enqueue_wrap(resident_id, key, number)
    end
  end

  # Stopped (brain#61): the run ends unwrapped and the loop rests until
  # either party touches the queue; no wrap, no next check.
  defp carry_on(resident_id, _key, number, _n, %{stopped: _by}) do
    ended =
      dispatch(%Commands.EndWork{
        actor: @actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        stopped: true
      })

    with {:ok, _} <- ended, do: :ok
  end

  defp carry_on(resident_id, key, number, n, %{rounds_spent: true}) do
    if n < Config.fetch!(:sunna, :work_turns),
      do: worker().enqueue(resident_id, key, number, n + 1),
      else: worker().enqueue_wrap(resident_id, key, number)

    :ok
  end

  defp carry_on(resident_id, key, number, _n, _done) do
    worker().enqueue_wrap(resident_id, key, number)
    :ok
  end

  @doc """
  The wrap (sunna#33): one closing turn in the run's conversation, in
  which she records what shipped, what slipped and why; billed to the
  `planning` line as free time's closing turn is (sunna#32), so a run
  ended by its budget is still wrapped. Then the run ends, and its end
  buys the next check.
  """
  def wrap_turn(resident_id, key, number) do
    case running?(resident_id, number, key) && care_wait(resident_id) do
      false ->
        :ok

      nil ->
        _ = Wakes.run(resident_id, "work", [%{kind: "work_wrap", number: number}])

        result =
          case wake(resident_id, key, Prompt.render!("work_wrap", %{number: number}), :planning) do
            # Outlasted, the wrap still runs on and records itself (sunna#67).
            {:error, %{kind: :brain_wake_outlasted}} -> {:ok, :outlasted}
            other -> other
          end

        close(resident_id, key, number, result)

      wait ->
        {:snooze, wait}
    end
  end

  defp close(resident_id, _key, number, result) do
    ended =
      dispatch(%Commands.EndWork{actor: @actor, at: Clock.now(), id: resident_id, number: number})

    # A run that ended in an error waits before the next check (sunna#52):
    # the same item would start again at once, fail the same way, and a
    # day's runs went in eight minutes of empty conversations (2026-11-11).
    # A wrap still running (sunna#67) waits the same, so the next check
    # never finds its item open again before the wrap records it.
    if waits?(result),
      do: worker().enqueue_check(resident_id, Config.fetch!(:sunna, :work_retry_seconds)),
      else: worker().enqueue_check(resident_id)

    case {result, ended} do
      {{:error, _} = failed, _} -> failed
      {_ok, {:ok, _}} -> :ok
      {_ok, failed} -> failed
    end
  end

  defp waits?({:error, _}), do: true
  defp waits?({:ok, :outlasted}), do: true
  defp waits?(_ok), do: false

  @doc "Whether the tick should ask for a check: the line on, work waiting, nothing running."
  def due?(resident_id) do
    Scope.resident(resident_id, fn ->
      state = Store.work_queue()
      items = Store.work_items()

      # A run left behind is asked about armed or not (sunna#41): the
      # check is the only place that ends it.
      (state != nil and left_behind?(state, items)) or on_and_waiting?(resident_id, state, items)
    end)
  end

  # The house queue runs unless paused (sunna#94), no arm of hers; the old
  # queue runs while she has armed it.
  defp on_and_waiting?(resident_id, state, items) do
    if cut_over?(resident_id),
      do: house_waiting?(resident_id, state),
      else: old_waiting?(state, items)
  end

  defp house_waiting?(resident_id, state),
    do:
      house_running?(resident_id) and free?(state) and not stopped?(state) and
        activity_waiting?(resident_id)

  defp old_waiting?(nil, _items), do: false

  defp old_waiting?(state, items),
    do:
      state.armed and free?(state) and not stopped?(state) and
        Enum.any?(items, &(&1.status == "open"))

  defp stopped?(nil), do: false
  defp stopped?(state), do: state.rested_reason == Work.stopped_rest()

  defp free?(state), do: not busy?(state)

  defp busy?(nil), do: false
  defp busy?(state), do: not (is_nil(state.running) and is_nil(state.running_act))

  # A run whose item is no longer in work (sunna#41): moved by hand before
  # sunna#37 ended such runs, so the record still names it; ended by the
  # check like a stalled one, its item's status kept.
  defp orphaned?(%{running: n}, items) when is_integer(n),
    do: not Enum.any?(items, &(&1.number == n and &1.status == "in_work"))

  defp orphaned?(_state, _items), do: false

  # The item running, as the read says it: never one that is not in work.
  defp live(state, items) do
    if state != nil and is_integer(state.running) and not orphaned?(state, items),
      do: state.running,
      else: nil
  end

  # A run whose end was never recorded (sunna#37): its job died (a deploy
  # restart, a crash past its one attempt), so nothing would ever end it
  # and the loop would say it runs an item forever. Past
  # `SUNNA_WORK_RUN_STALE_MINUTES` the check ends it, and goes on.
  defp stalled?(%{running_act: a, running_since: %DateTime{} = since}) when is_binary(a) do
    stale = Config.fetch!(:sunna, :work_run_stale_minutes) * 60
    DateTime.diff(Clock.now(), since, :second) > stale
  end

  defp stalled?(%{running: n, running_since: %DateTime{} = since}) when is_integer(n) do
    stale = Config.fetch!(:sunna, :work_run_stale_minutes) * 60
    DateTime.diff(Clock.now(), since, :second) > stale
  end

  defp stalled?(_state), do: false

  # A run the check ends rather than waits on: stalled past the bound
  # (#37), its item no longer in work (#41), or no job left to carry it
  # (#70).
  defp left_behind?(state, items),
    do: stalled?(state) or orphaned?(state, items) or dead?(state)

  # A run with no job left to carry it (sunna#70): a restart killed its
  # turn mid-call, and a work job has one attempt, so nothing will end
  # it before the stale bound, three hours on (2026-11-18: item #60, its
  # first turn killed by a deploy a minute after it started). Every live
  # run has a turn, a wrap or a snoozed one waiting or executing; past a
  # short grace for the start's own enqueue, none means the run is gone,
  # and the check ends it so its item opens again.
  @dead_grace 120
  defp dead?(%{running_key: key, running_since: %DateTime{} = since} = state)
       when is_binary(key) and (is_integer(state.running) or is_binary(state.running_act)) do
    DateTime.diff(Clock.now(), since, :second) > @dead_grace and
      not Enum.any?(
        Scope.resident(state.resident_id, fn ->
          Jobs.states(worker(), %{"session_key" => key})
        end),
        &(&1 in ~w(available scheduled executing retryable))
      )
  end

  defp dead?(_state), do: false

  # Checks again only when the end was recorded: a record that ends
  # nothing must not be asked about forever.
  defp end_stalled(resident_id, %{running_act: act}) when is_binary(act) do
    case dispatch(%Commands.EndActivityRun{
           actor: @actor,
           at: Clock.now(),
           id: resident_id,
           act: act
         }) do
      {:ok, [_ended]} ->
        worker().enqueue_check(resident_id)
        :stalled

      other ->
        other
    end
  end

  defp end_stalled(resident_id, state) do
    case dispatch(%Commands.EndWork{
           actor: @actor,
           at: Clock.now(),
           id: resident_id,
           number: state.running
         }) do
      {:ok, [_ended]} -> check(resident_id)
      _nothing -> :running
    end
  end

  # Whether this run is still the one running: item `number`, in the
  # conversation `key`. A turn or wrap of a run that has ended (moved by
  # hand, stalled and ended) does nothing, and so does one of an earlier
  # run of the same item, whose conversation is not the run's (sunna#67).
  defp running?(resident_id, number, key) do
    match?(
      %{running: ^number, running_key: ^key},
      Scope.resident(resident_id, fn -> Store.work_queue() end)
    )
  end

  # ---- the house queue's activities (sunna#86) ----

  # After the cutover the line runs her house queue: the first of her
  # ready or active activities in Waiting-on-me order (blocking-most,
  # then oldest ready), taken at the run's start and run a turn at a time
  # in a `work` conversation, under the same line, care, budget and cap.
  defp next_activity(resident_id, state, line, cap) do
    card = first_activity(resident_id)

    cond do
      # One switch for the house (sunna#94): her line runs while the
      # house queue does, whatever her old arm said.
      not house_running?(resident_id) ->
        rest(resident_id, "paused: the house queue is paused")

      # Nothing ready is no reason to stop (sunna#92, #94): the house's
      # work arrives any time, and the tick starts it once it is ready.
      is_nil(card) ->
        rest(resident_id, "running, holding: nothing in the house queue is ready for you")

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
    do: cut_over?(resident_id) and not is_nil(first_activity(resident_id))

  defp first_activity(resident_id) do
    case Oneiroi.Gaia.resident_household(resident_id) do
      %{id: h} ->
        h
        |> Queues.waiting_on("resident:#{resident_id}")
        |> Map.fetch!(:ready)
        |> Enum.find(&(&1.view in ["ready", "active"]))
        |> then(&(&1 && Map.put(&1, :household, h)))

      _none ->
        nil
    end
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
        act: act
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

  defp layer_line({acts, i}),
    do:
      "#{i}. " <>
        Enum.map_join(acts, "; ", fn a ->
          "#{a.act_id} #{a.type} (#{a.assignee}, #{a.view})#{if a.note, do: ": " <> a.note, else: ""}"
        end)

  # ---- the note ----

  defp note(resident_id, number, 1, left) do
    {items, row} = {Scope.resident(resident_id, fn -> Store.work_items() end), name(resident_id)}
    item = Enum.find(items, &(&1.number == number))

    Prompt.render!("work", %{
      name: row,
      number: number,
      what: item.what,
      done_when: item.done_when,
      last: last_wrap(item),
      queue: Enum.map_join(items, "\n", &line/1),
      turns: Config.fetch!(:sunna, :work_turns),
      left: left
    })
  end

  defp note(_resident_id, number, n, left),
    do:
      Prompt.render!("work_continue", %{
        number: number,
        turn: n,
        turns: Config.fetch!(:sunna, :work_turns),
        left: left
      })

  defp last_wrap(%{wrapped_at: nil}), do: "This is the item's first run."

  defp last_wrap(item),
    do:
      "Its last run's wrap: shipped: #{item.shipped}" <>
        if(item.slipped, do: "; slipped: #{item.slipped}", else: "") <> "; why: #{item.why}."

  defp line(item) do
    "#{item.number}. [#{item.status}#{on(item)}] #{item.what} (added by #{item.added_by})"
  end

  defp on(%{status: "held", held_ask: ask}) when is_binary(ask), do: ": #{ask}"
  defp on(%{blocked_on: on}) when is_binary(on), do: " on #{on}"
  defp on(_item), do: ""

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
    if Scope.resident(resident_id, fn ->
         Store.free_time_underway?(free_time_since(resident_id))
       end),
       do: @care_wait,
       else: nil
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

  defp care_first?(resident_id) do
    since = free_time_since(resident_id)
    Scope.resident(resident_id, fn -> Store.free_time_underway?(since) end)
  end

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
        if :blocked_on_too_long in problems,
          do: {:error, Error.new(:sunna_work_blocked_on_invalid, :sunna_work_blocked_on_bound)},
          else: {:error, Error.new(:sunna_work_invalid, :sunna_work_field_bound)}

      {:error, reason} ->
        {:error, Error.caught(:sunna_dispatch_failed, :sunna_work_dispatch_failed, reason)}
    end
  end
end
