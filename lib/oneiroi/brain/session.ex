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
  @spec submit(String.t(), String.t(), String.t(), Oneiroi.Actor.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def submit(resident_id, session_key, text, actor, ref) when is_binary(ref) do
    with {:ok, pid} <- ensure(resident_id, session_key) do
      GenServer.call(pid, {:submit, %{ref: ref, text: text, actor: actor, opts: []}})
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
        opts = Keyword.put(item.opts, :turn_ref, item.ref)

        task =
          Task.Supervisor.async_nolink(@tasks, fn ->
            Turn.run(id, key, item.text, item.actor, opts)
          end)

        %{state | queue: queue, running: Map.put(item, :task, task)}

      {:empty, _queue} ->
        %{state | running: nil}
    end
  end

  defp done(%{running: item} = state, result) do
    if item.from, do: GenServer.reply(item.from, result)
    recent = Enum.take([item.ref | state.recent], @recent)
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
