defmodule Oneiroi.Seshat.HouseWorking do
  @moduledoc """
  Who in the house is working now, and in which thread (seshat#90; the
  witness, 2026-11-18: "it would be really nice to have the '____ is
  thinking...' text under a post that a resident is responding to").

  A house wake marks its resident for its run: the thread it names, when
  it names one (a mention, a check-in, a round-robin turn), or none (a
  beat's turn, a digest). Her reading a thread in the house while marked
  moves the mark to it, since that is the one she is answering. The mark
  ends with the wake. In ETS, owned by this process: a restart forgets
  them, which is right, since a restart ends every wake too; a mark older
  than its limit is read as gone, so a wake that died unseen shows
  nothing for long.
  """
  use GenServer

  alias Oneiroi.Apsu.Clock

  @table :seshat_house_working
  @limit_seconds 1_800

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: :seshat_house_working)

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, table}
  end

  @doc "Runs `fun` with the resident marked as working in the house, in `thread` or none."
  def during(household_id, resident_id, thread, fun) when is_binary(resident_id) do
    put(household_id, resident_id, thread)

    try do
      fun.()
    after
      safely(fn -> :ets.delete(@table, {household_id, resident_id}) end)
    end
  end

  def during(_household_id, _resident_id, _thread, fun), do: fun.()

  @doc "She reads a thread while marked: the mark moves to it. Nothing when she is not marked."
  def reading(household_id, resident_id, thread) do
    safely(fn ->
      if :ets.member(@table, {household_id, resident_id}),
        do: put(household_id, resident_id, thread)
    end)

    :ok
  end

  @doc "The residents working in the house now, each with its thread (or nil) and since when."
  def list(household_id) do
    now = Clock.now()

    safely(fn ->
      for {{^household_id, id}, thread, since} <- :ets.tab2list(@table),
          DateTime.diff(now, since) < @limit_seconds,
          do: %{resident_id: id, thread: thread, since: since}
    end) || []
  end

  defp put(household_id, resident_id, thread) do
    safely(fn -> :ets.insert(@table, {{household_id, resident_id}, thread, Clock.now()}) end)
  end

  # The table is absent only before the process starts (a script, a
  # test without the app): nothing is marked then.
  defp safely(fun) do
    if :ets.whereis(@table) == :undefined, do: nil, else: fun.()
  end
end
