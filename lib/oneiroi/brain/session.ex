defmodule Oneiroi.Brain.Session do
  @moduledoc """
  One process per active session (spec §5), started on the first turn.
  Its job is to run the session's turns one at a time, so two messages
  sent at once do not interleave their captures (brain#45).

  It keeps a queue and nothing the event store needs: the turns waiting,
  the one running (in a supervised task, so the process stays free to
  take the next message while a turn runs), and the refs it has seen
  lately, so a client's retry of a message it already took is answered
  as a duplicate rather than run twice. A turn whose ref is already
  captured is a duplicate too, across a restart.

  Two ways in. `submit/5` takes a message under the client's own ref and
  answers at once, `running` or `queued` or `duplicate`; the outcome
  arrives on the session topic like every other event of the turn. The
  synchronous `turn/4` and `wake/4` go through the same queue and answer
  when their turn is done, as they always have.
  """
  use GenServer

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu

  @registry :brain_registry
  @supervisor :brain_sessions
  @tasks :brain_turns

  # How many refs a session remembers beyond the ones in the store, so a
  # retry that crosses a turn's end is still a duplicate.
  @recent 200

  @doc "Runs a turn on the session's process and answers when it is done, starting the process if it is not running."
  @spec turn(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  def turn(resident_id, session_key, text, actor) do
    with {:ok, pid} <- ensure(resident_id, session_key) do
      item = %{ref: nil, text: text, actor: actor, opts: []}
      GenServer.call(pid, {:run, item}, Config.fetch!(:brain, :turn_timeout_ms))
    end
  end

  @doc """
  Takes a message under the client's ref and answers at once: `running`
  when it starts now, `queued` with how many wait ahead, or `duplicate`
  when the ref was taken before (brain#45).
  """
  @spec submit(String.t(), String.t(), String.t(), Oneiroi.Actor.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def submit(resident_id, session_key, text, actor, ref, opts \\ []) when is_binary(ref) do
    # The composer's domain (kumbukumbu#72), carried on the item and
    # named when its turn starts, never when it is queued: a message
    # waiting behind a running turn must not move that turn's domain.
    opts = Keyword.take(opts, [:domain])

    with {:ok, pid} <- ensure(resident_id, session_key) do
      GenServer.call(
        pid,
        {:submit, %{ref: ref, text: text, actor: actor, opts: opts, taken_at: Clock.now()}}
      )
    end
  end

  @doc "Asks the running turn to stop (brain#61); an error when none runs here."
  @spec stop(String.t(), String.t(), atom()) :: :ok | {:error, term()}
  def stop(resident_id, session_key, by) do
    case Registry.lookup(@registry, {resident_id, session_key}) do
      [{pid, _}] -> GenServer.call(pid, {:stop, by})
      [] -> {:error, Error.new(:brain_nothing_running, :brain_session_stop_no_process)}
    end
  end

  @doc "Runs a wake on the session's process: the core's note, answered under its purpose."
  @spec wake(String.t(), String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def wake(resident_id, session_key, note, purpose) do
    with {:ok, pid} <- ensure(resident_id, session_key) do
      item = %{ref: nil, text: note, actor: Actor.platform(), opts: [as: :note, purpose: purpose]}
      GenServer.call(pid, {:run, item}, Config.fetch!(:brain, :turn_timeout_ms))
    end
  end

  def start_link({resident_id, session_key}) do
    GenServer.start_link(__MODULE__, {resident_id, session_key},
      name: via(resident_id, session_key)
    )
  end

  @impl GenServer
  def init({resident_id, session_key}) do
    {:ok,
     %{
       resident_id: resident_id,
       session_key: session_key,
       queue: :queue.new(),
       running: nil,
       recent: []
     }}
  end

  @impl GenServer
  def handle_call({:run, item}, from, state) do
    item = %{item | ref: item.ref || Kumbukumbu.turn_ref()}
    {:noreply, enqueue(state, Map.put(item, :from, from))}
  end

  def handle_call({:stop, by}, _from, %{running: %{task: %Task{pid: pid}}} = state) do
    send(pid, {:brain_stop, by})
    {:reply, :ok, state}
  end

  def handle_call({:stop, _by}, _from, state),
    do: {:reply, {:error, Error.new(:brain_nothing_running, :brain_session_stop_idle)}, state}

  def handle_call({:submit, item}, _from, state) do
    if seen?(state, item.ref) or claimed_elsewhere?(state, item) do
      {:reply, {:ok, %{turn_ref: item.ref, state: "duplicate"}}, state}
    else
      ahead = :queue.len(state.queue) + if(state.running, do: 1, else: 0)
      state = enqueue(state, Map.put(item, :from, nil))
      answer = if ahead == 0, do: "running", else: "queued"

      if ahead > 0,
        do: status(state, item.ref, "queued", %{ahead: ahead})

      {:reply, {:ok, %{turn_ref: item.ref, state: answer, ahead: ahead}}, state}
    end
  end

  # The running turn's task answered: reply to a waiting caller, keep its
  # ref, start the next.
  @impl GenServer
  def handle_info({task_ref, result}, %{running: %{task: %Task{ref: task_ref}}} = state) do
    Process.demonitor(task_ref, [:flush])
    {:noreply, done(state, result)}
  end

  # The task died before answering: the caller gets the failure, and the
  # next message still runs.
  def handle_info(
        {:DOWN, task_ref, :process, _pid, reason},
        %{running: %{task: %Task{ref: task_ref}}} = state
      ) do
    failure = Error.caught(:brain_turn_crashed, :brain_session_turn_crashed, reason)
    crashed(state, state.running, failure)
    {:noreply, done(state, {:error, failure})}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # ---- the queue ----

  defp enqueue(state, item) do
    state = %{state | queue: :queue.in(item, state.queue)}
    if state.running, do: state, else: next(state)
  end

  defp next(state) do
    case :queue.out(state.queue) do
      {{:value, item}, queue} ->
        %{resident_id: id, session_key: key} = state
        {followers, queue} = followers(item, queue, Config.fetch!(:brain, :batch_messages) - 1)
        batch = [item | followers]
        last = List.last(batch)

        # Batched delivery (brain#66): the turn runs under the oldest
        # message's ref; the newest opens it, the rest come before it,
        # and each one joined says which turn it went into.
        opts =
          item.opts
          |> Keyword.delete(:domain)
          |> Keyword.put(:turn_ref, item.ref)
          |> Keyword.put(:earlier, Enum.map(Enum.drop(batch, -1), &said/1))

        # The batch's domain is its newest message's that named one.
        domain = batch |> Enum.filter(&Keyword.has_key?(&1.opts, :domain)) |> List.last()

        for f <- followers, do: status(state, f.ref, "batched", %{into: item.ref})

        task =
          Task.Supervisor.async_nolink(@tasks, fn ->
            timed_turn(id, key, item, last, opts, domain)
          end)

        running = item |> Map.put(:task, task) |> Map.put(:batch, batch)
        %{state | queue: queue, running: running}

      {:empty, _queue} ->
        %{state | running: nil}
    end
  end

  # A turn is a unit of work the span collector times (apsu#26).
  defp timed_turn(id, key, item, last, opts, domain) do
    :telemetry.span(
      [:oneiroi, :brain, :turn],
      %{resident_id: id, kind: Keyword.get(item.opts, :purpose, :chat)},
      fn ->
        tag_domain(id, key, item.ref, domain)
        {Turn.run(id, key, last.text, last.actor, opts), %{resident_id: id}}
      end
    )
  end

  # The turn named into the domain its message carried, before it runs,
  # so its capture lands there and its context is assembled there.
  defp tag_domain(_id, _key, _ref, nil), do: :ok

  defp tag_domain(id, key, ref, item) do
    case Kumbukumbu.tag_domain(id, key, ref, nil, item.opts[:domain], item.actor) do
      :ok -> :ok
      {:error, _refused} -> :ok
    end
  end

  # The witness's messages waiting behind a batchable one, up to `room`
  # more: only his own messages by `submit` join (a synchronous caller
  # and a wake each keep their own turn), and only while they come in a
  # row.
  defp followers(item, queue, room) do
    if batchable?(item), do: take_followers(queue, room, []), else: {[], queue}
  end

  defp take_followers(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_followers(queue, room, acc) do
    case :queue.peek(queue) do
      {:value, next} ->
        if batchable?(next),
          do: take_followers(:queue.drop(queue), room - 1, [next | acc]),
          else: {Enum.reverse(acc), queue}

      :empty ->
        {Enum.reverse(acc), queue}
    end
  end

  defp batchable?(item), do: is_nil(item.from) and item.opts == []

  defp said(item),
    do: %{text: item.text, actor: item.actor, sent_at: Map.get(item, :taken_at) || Clock.now()}

  # A turn that died said nothing on its way out (brain#54): the witness's
  # words are kept, the failure recorded where a client reads it back and
  # broadcast to one that is listening, and the operator's log says so. A
  # wake's note is the core's and is not kept as if someone had said it.
  defp crashed(state, item, failure) do
    %{resident_id: id, session_key: key} = state
    resident = Actor.new(:resident, id)
    reason = "the turn stopped on a fault before it answered"

    if Keyword.get(item.opts, :as) != :note,
      do:
        Kumbukumbu.capture(
          id,
          key,
          item.ref,
          Clock.now(),
          for(
            m <- Map.get(item, :batch, [item]),
            do: %{
              role: :user,
              content: m.text,
              sent_at: Map.get(m, :taken_at) || Clock.now(),
              actor: m.actor
            }
          ),
          resident
        )

    Kumbukumbu.fail_capture(id, key, item.ref, reason, resident)
    Turn.broadcast(id, key, {:failed, item.ref, reason})

    Logger.error(
      "brain: a turn crashed (#{item.ref})",
      [component: "brain"] ++ Oneiroi.Error.metadata(failure)
    )
  end

  defp done(%{running: item} = state, result) do
    if item.from, do: GenServer.reply(item.from, result)
    recent = Enum.take(Enum.map(Map.get(item, :batch, [item]), & &1.ref) ++ state.recent, @recent)
    next(%{state | running: nil, recent: recent})
  end

  # The claim on the stream (kumbukumbu#47): what this process's memory
  # cannot know, another instance's turn under the same ref (a deploy's
  # overlap) or this process's own before a restart. A claim older than
  # the turn timeout, never captured, died with its turn and is taken
  # again. A claim that could not be recorded lets the message run: a
  # rare second turn is better than a lost message.
  defp claimed_elsewhere?(state, item) do
    stale_before =
      DateTime.add(
        Clock.now(),
        -Config.fetch!(:brain, :turn_timeout_ms),
        :millisecond
      )

    case Kumbukumbu.claim_turn(
           state.resident_id,
           state.session_key,
           item.ref,
           stale_before,
           item.actor
         ) do
      :duplicate -> true
      _claimed_or_failed -> false
    end
  end

  defp seen?(state, ref) do
    ref in state.recent or
      match?(%{ref: ^ref}, state.running) or
      (state.running != nil and Enum.any?(Map.get(state.running, :batch, []), &(&1.ref == ref))) or
      Enum.any?(:queue.to_list(state.queue), &(&1.ref == ref)) or
      Kumbukumbu.turn_messages(state.resident_id, ref) != []
  end

  defp status(state, ref, what, detail),
    do: Turn.broadcast(state.resident_id, state.session_key, {:status, ref, what, detail})

  defp ensure(resident_id, session_key) do
    case Registry.lookup(@registry, {resident_id, session_key}) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(@supervisor, {__MODULE__, {resident_id, session_key}}) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}

          {:error, reason} ->
            {:error, Error.caught(:brain_session_unavailable, :brain_session_not_started, reason)}
        end
    end
  end

  defp via(resident_id, session_key),
    do: {:via, Registry, {@registry, {resident_id, session_key}}}
end
