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

  Care outranks work: no work turn starts inside quiet hours or while a
  free-time pass is underway; one that would is put off and tried
  again. The queue accelerates her drafting, never the witness's
  deciding: the run's note says so, and nothing here acts on the
  platform.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.Store
  alias Oneiroi.Sunna.Work
  alias Oneiroi.Sunna.WorkRouter

  @actor Actor.new(:job, "sunna_work")
  # How long a free-time pass is taken to be underway at most, when its
  # planning turn never closed it.
  @free_time_window 3 * 3600
  # How long a work turn waits when care comes first.
  @care_wait 600

  # ---- the queue's edge ----

  @doc "Adds an item to the end of the queue; returns its number."
  def add(resident_id, what, done_when, %Actor{} = actor) do
    command = %Commands.AddWork{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      what: what,
      done_when: done_when
    }

    case dispatch(command) do
      {:ok, [event]} -> {:ok, event.number}
      {:ok, []} -> {:error, Error.new(:sunna_work_invalid, :sunna_work_add_not_recorded)}
      other -> other
    end
  end

  @doc "Moves an item's status (open, blocked with what blocks it, done, dropped), with a note."
  def move(resident_id, number, status, blocked_on, note, %Actor{} = actor) do
    command = %Commands.MoveWork{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      status: status,
      blocked_on: blocked_on,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Puts the numbers given first, in that order; the rest keep theirs after."
  def order(resident_id, numbers, %Actor{} = actor) do
    command = %Commands.OrderWork{actor: actor, at: Clock.now(), id: resident_id, order: numbers}
    with {:ok, _} <- dispatch(command), do: :ok
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
      blocked_on: attrs[:blocked_on]
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
            :session_key
          ])
        ),
      running: live(state, items),
      running_since: live(state, items) && state.running_since,
      rested: state && state.rested_reason,
      rested_at: state && state.rested_at,
      runs_today: runs_today(resident_id, state),
      runs_a_day: Config.fetch!(:sunna, :work_runs_a_day),
      budget: budget(resident_id),
      # Armed by her for a batch, off once the queue clears (sunna#35).
      armed: (state && state.armed) || false,
      armed_at: state && state.armed_at,
      # Who armed it (sunna#43): "resident" by her tool, "witness" by his button.
      armed_by: state && state.armed_by
    }
  end

  # ---- the loop ----

  @doc """
  The queue check: starts the first open item, or rests and says why.
  Nothing while an item runs, or while care comes first (the tick and
  the run's end ask again).
  """
  def check(resident_id) do
    {items, state, settings} =
      Scope.resident(resident_id, fn ->
        {Store.work_items(), Store.work_queue(), Store.settings()}
      end)

    cond do
      stalled?(state) or orphaned?(state, items) -> end_stalled(resident_id, state)
      state && state.running -> :running
      state && state.rested_reason == Work.stopped_rest() -> :stopped
      care_first?(resident_id, settings) -> :care
      true -> next(resident_id, items, state)
    end
  end

  defp next(resident_id, items, state) do
    open = Enum.find(items, &(&1.status == "open"))
    line = budget(resident_id)
    cap = Config.fetch!(:sunna, :work_runs_a_day)

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

  defp empty(items) do
    case Enum.filter(items, &(&1.status == "blocked")) do
      [] ->
        "empty, holding"

      blocked ->
        "empty, holding: " <>
          Enum.map_join(blocked, "; ", &"##{&1.number} blocked on #{&1.blocked_on}")
    end
  end

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
    with true <- running?(resident_id, number),
         nil <- care_wait(resident_id),
         {:ok, left} <- allowance(resident_id),
         true <- n <= Config.fetch!(:sunna, :work_turns),
         {:ok, result} <- wake(resident_id, key, note(resident_id, number, n, left), :work) do
      carry_on(resident_id, key, number, n, result)
    else
      false -> :ok
      wait when is_integer(wait) -> {:snooze, wait}
      {:error, _} = failed -> close(resident_id, key, number, failed)
      _spent -> worker().enqueue_wrap(resident_id, key, number)
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
    case running?(resident_id, number) && care_wait(resident_id) do
      false ->
        :ok

      nil ->
        result = wake(resident_id, key, Prompt.render!("work_wrap", %{number: number}), :planning)
        close(resident_id, key, number, result)

      wait ->
        {:snooze, wait}
    end
  end

  defp close(resident_id, _key, number, result) do
    ended =
      dispatch(%Commands.EndWork{actor: @actor, at: Clock.now(), id: resident_id, number: number})

    worker().enqueue_check(resident_id)

    case {result, ended} do
      {{:error, _} = failed, _} -> failed
      {_ok, {:ok, _}} -> :ok
      {_ok, failed} -> failed
    end
  end

  @doc "Whether the tick should ask for a check: the line armed, work open, nothing running."
  def due?(resident_id) do
    Scope.resident(resident_id, fn ->
      state = Store.work_queue()
      items = Store.work_items()

      # A run left behind is asked about armed or not (sunna#41): the
      # check is the only place that ends it.
      (state != nil and (stalled?(state) or orphaned?(state, items))) or
        (state != nil and state.armed and is_nil(state.running) and
           state.rested_reason != Work.stopped_rest() and
           Enum.any?(items, &(&1.status == "open")))
    end)
  end

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
  defp stalled?(%{running: n, running_since: %DateTime{} = since}) when is_integer(n) do
    stale = Config.fetch!(:sunna, :work_run_stale_minutes) * 60
    DateTime.diff(Clock.now(), since, :second) > stale
  end

  defp stalled?(_state), do: false

  # Checks again only when the end was recorded: a record that ends
  # nothing must not be asked about forever.
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

  # Whether item `number` is still the one running: a turn or wrap of a
  # run that has ended (moved by hand, or stalled and ended) does nothing.
  defp running?(resident_id, number) do
    match?(%{running: ^number}, Scope.resident(resident_id, fn -> Store.work_queue() end))
  end

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
    blocked = if item.blocked_on, do: " on #{item.blocked_on}", else: ""
    "#{item.number}. [#{item.status}#{blocked}] #{item.what} (added by #{item.added_by})"
  end

  # ---- care, budget, state ----

  # How long a run's next turn waits for care, or nil when it may go on.
  # Paused, never restarted (her ask, letter #185: dormant is not
  # abandoned): the same turn of the same run in the same conversation
  # runs when care is done. Inside quiet hours it waits until they end;
  # behind a free-time pass, ten minutes at a time until its planning
  # turn closes it.
  defp care_wait(resident_id) do
    quiet = quiet_of(settings(resident_id))
    local = Schedules.local_now(resident_id)
    since = DateTime.add(Clock.now(), -@free_time_window, :second)

    cond do
      Schedules.quiet?(local, quiet) ->
        max(DateTime.diff(Schedules.quiet_end(local, quiet), local, :second), 60)

      Scope.resident(resident_id, fn -> Store.free_time_underway?(since) end) ->
        @care_wait

      true ->
        nil
    end
  end

  defp care_first?(resident_id, settings) do
    local = Schedules.local_now(resident_id)
    since = DateTime.add(Clock.now(), -@free_time_window, :second)

    Schedules.quiet?(local, quiet_of(settings)) or
      Scope.resident(resident_id, fn -> Store.free_time_underway?(since) end)
  end

  defp quiet_of(%{quiet_from: from, quiet_to: to}) when is_binary(from) and is_binary(to),
    do: %{from: from, to: to}

  defp quiet_of(_settings), do: nil

  defp settings(resident_id), do: Scope.resident(resident_id, fn -> Store.settings() end)

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
