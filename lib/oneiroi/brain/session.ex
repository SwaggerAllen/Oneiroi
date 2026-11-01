defmodule Oneiroi.Brain.Session do
  @moduledoc """
  One process per active session (spec §5), started on the first turn
  and holding nothing the event store does not (conventions §5): its
  state is the resident and the session key, and its one job is to run
  the session's turns one at a time, so two messages sent at once do not
  interleave their captures.
  """
  use GenServer

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Config

  @registry :brain_registry
  @supervisor :brain_sessions

  @doc "Runs a turn on the session's process, starting it if it is not running."
  @spec turn(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  def turn(resident_id, session_key, text, actor) do
    with {:ok, pid} <- ensure(resident_id, session_key) do
      GenServer.call(pid, {:turn, text, actor}, Config.fetch!(:brain, :turn_timeout_ms))
    end
  end

  @doc "Runs a wake on the session's process: the core's note, answered under its purpose."
  @spec wake(String.t(), String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def wake(resident_id, session_key, note, purpose) do
    with {:ok, pid} <- ensure(resident_id, session_key) do
      GenServer.call(pid, {:wake, note, purpose}, Config.fetch!(:brain, :turn_timeout_ms))
    end
  end

  def start_link({resident_id, session_key}) do
    GenServer.start_link(__MODULE__, {resident_id, session_key},
      name: via(resident_id, session_key)
    )
  end

  @impl GenServer
  def init({resident_id, session_key}),
    do: {:ok, %{resident_id: resident_id, session_key: session_key}}

  @impl GenServer
  def handle_call({:turn, text, actor}, _from, state) do
    {:reply, Turn.run(state.resident_id, state.session_key, text, actor), state}
  end

  def handle_call({:wake, note, purpose}, _from, state) do
    opts = [as: :note, purpose: purpose]
    {:reply, Turn.run(state.resident_id, state.session_key, note, Actor.platform(), opts), state}
  end

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
