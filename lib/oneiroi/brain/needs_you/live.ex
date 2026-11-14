defmodule Oneiroi.Brain.NeedsYou.Live do
  @moduledoc """
  The bell pushed, not pulled (brain#94; the witness, 2026-11-13: "make
  it an event based push rather than a pull"). A client used to read
  `needs_you` again on every change notice, and each read computes the
  list across every source: during her turns that was a read every few
  seconds per tab, and on 2026-11-13 at 22:31Z a dozen abandoned ones
  held the connection pool while her free time needed it.

  Now this process hears the change notices (apsu#24) and, for a resident
  someone is watching (a client's resident channel registers itself,
  `watch/1`), gathers a burst for `@gather_ms` and computes the list once,
  off its own process, broadcasting it on the `needs_you` topic for the
  channel to push. Nobody watching, nothing is computed. A read
  (`GET /needs_you`) still computes the list whole, so it is never
  stale; it is asked once, when the bell mounts, and after an act of his.
  """
  use GenServer

  require Logger

  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.NeedsYou

  # How long a burst of notices is gathered before the list is computed:
  # a turn folds many events in a second, and one list answers them all.
  @gather_ms 1_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: :brain_needs_you_live)

  @doc "Registers the calling process as watching `resident_id`'s bell, until it exits."
  @spec watch(String.t()) :: :ok
  def watch(resident_id) do
    {:ok, _owner} = Registry.register(:brain_needs_you_watchers, resident_id, nil)
    :ok
  end

  @impl GenServer
  def init(:ok) do
    :ok = PubSub.subscribe(:apsu, :notices)
    {:ok, %{gathering: MapSet.new()}}
  end

  @impl GenServer
  def handle_info({:oneiroi, _topic, _payload, _trace} = envelope, state) do
    case PubSub.receive(envelope) do
      {resident_id, _notice} when is_binary(resident_id) ->
        {:noreply, gather(state, resident_id)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:compute, resident_id}, state) do
    if watched?(resident_id), do: compute(resident_id)
    {:noreply, %{state | gathering: MapSet.delete(state.gathering, resident_id)}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp gather(state, resident_id) do
    cond do
      MapSet.member?(state.gathering, resident_id) ->
        state

      not watched?(resident_id) ->
        state

      true ->
        Process.send_after(self(), {:compute, resident_id}, @gather_ms)
        %{state | gathering: MapSet.put(state.gathering, resident_id)}
    end
  end

  defp watched?(resident_id),
    do: Registry.lookup(:brain_needs_you_watchers, resident_id) != []

  # Off this process, so one slow list never delays another resident's,
  # and a failure is the push's alone: the next notice or read answers.
  defp compute(resident_id) do
    Task.Supervisor.start_child(:brain_turns, fn ->
      entries = NeedsYou.list(resident_id)
      PubSub.broadcast(:brain, :needs_you, {resident_id, entries})
    end)
  end
end
