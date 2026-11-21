defmodule Oneiroi.Kumbukumbu.TurnReads do
  @moduledoc """
  What a turn read deliberately, by its resident and turn (kumbukumbu#80): a bookmark
  opened, a transcript read, each with its labels, so the turn's input
  ledger knows what reached the model beyond what was assembled. In ETS,
  owned by this process: a restart forgets them, which a restart's ending
  of every turn makes right; an entry older than two hours is dropped
  the next time any turn writes.
  """
  use GenServer

  alias Oneiroi.Apsu.Clock

  @table :kumbukumbu_turn_reads
  @keep_seconds 7_200

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: :kumbukumbu_turn_reads)

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :bag, read_concurrency: true])
    {:ok, table}
  end

  @doc "A resident's turn read these inputs."
  def note(resident_id, turn_ref, inputs) when is_binary(turn_ref) and is_list(inputs) do
    now = Clock.now()

    safely(fn ->
      sweep(now)
      for i <- inputs, do: :ets.insert(@table, {{resident_id, turn_ref}, i, now})
    end)

    :ok
  end

  def note(_resident_id, _turn_ref, _inputs), do: :ok

  @doc "What a resident's turn was assembled from, for an audience past the dyad (kumbukumbu#81): replaces the raw window in its ledger."
  def assembled(resident_id, turn_ref, inputs) when is_binary(turn_ref) and is_list(inputs) do
    now = Clock.now()

    safely(fn ->
      sweep(now)
      :ets.delete(@table, {resident_id, turn_ref, :assembled})
      :ets.insert(@table, {{resident_id, turn_ref, :assembled}, inputs, now})
    end)

    :ok
  end

  def assembled(_resident_id, _turn_ref, _inputs), do: :ok

  @doc """
  The words of a turn's sections that may hold restricted material,
  `%{name => text}` (kumbukumbu#82): what the disclosure judge is shown
  when one of them held back a delivery. Kept as long as the reads.
  """
  def sections(resident_id, turn_ref, texts) when is_binary(turn_ref) and is_map(texts) do
    now = Clock.now()

    safely(fn ->
      sweep(now)
      :ets.delete(@table, {resident_id, turn_ref, :sections})
      :ets.insert(@table, {{resident_id, turn_ref, :sections}, texts, now})
    end)

    :ok
  end

  def sections(_resident_id, _turn_ref, _texts), do: :ok

  @doc "A turn's section words, `%{}` when none were kept."
  def sections_of(resident_id, turn_ref) when is_binary(turn_ref) do
    safely(fn ->
      case :ets.lookup(@table, {resident_id, turn_ref, :sections}) do
        [{_, texts, _}] -> texts
        [] -> %{}
      end
    end) || %{}
  end

  def sections_of(_resident_id, _turn_ref), do: %{}

  @doc "What a resident's turn was assembled from, or nil when nothing was recorded."
  def assembled_of(resident_id, turn_ref) when is_binary(turn_ref) do
    safely(fn ->
      case :ets.lookup(@table, {resident_id, turn_ref, :assembled}) do
        [{_, inputs, _}] -> inputs
        [] -> nil
      end
    end)
  end

  def assembled_of(_resident_id, _turn_ref), do: nil

  @doc "What a resident's turn read, oldest first."
  def of(resident_id, turn_ref) when is_binary(turn_ref),
    do:
      safely(fn -> for {_, i, _} <- :ets.lookup(@table, {resident_id, turn_ref}), do: i end) || []

  def of(_resident_id, _turn_ref), do: []

  defp sweep(now) do
    cutoff = DateTime.add(now, -@keep_seconds, :second)

    for {ref, _i, at} <- :ets.tab2list(@table),
        DateTime.compare(at, cutoff) == :lt,
        uniq: true,
        do: :ets.delete(@table, ref)
  end

  # Absent before the process starts (a script, a test without the app).
  defp safely(fun), do: if(:ets.whereis(@table) == :undefined, do: nil, else: fun.())
end
