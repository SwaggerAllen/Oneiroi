defmodule Oneiroi.Brain.Progress do
  @moduledoc """
  Where a running turn is, for a view that has to tell working from hung
  (brain#119; the witness, 2026-11-25: "We also *need* some kind of
  intermediate status report in history at the bottom of the task page to
  see if something is hanging"): by resident and conversation, the turn,
  when it started, what it is doing (the model answering, or a tool by
  name), since when, and how many rounds and tool calls it has made.
  Receipts only, never words: a work conversation's words are hers.

  Kept from the turn's own status broadcasts in ETS owned by this
  process; a restart forgets it, as a restart ends every turn.
  """
  use GenServer

  alias Oneiroi.Apsu.Clock

  @table :brain_progress

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: :brain_progress)

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, table}
  end

  @doc "A turn's status: `thinking` (a round's call to the model) or `tool` with its name."
  def note(resident_id, session_key, turn_ref, what, detail) do
    now = Clock.now()

    safely(fn ->
      before =
        case :ets.lookup(@table, {resident_id, session_key}) do
          [{_, %{turn_ref: ^turn_ref} = p}] -> p
          _new_turn -> %{turn_ref: turn_ref, started_at: now, rounds: 0, calls: 0}
        end

      p =
        case what do
          "thinking" -> %{before | rounds: before.rounds + 1}
          "tool" -> %{before | calls: before.calls + 1}
          _other -> before
        end

      :ets.insert(
        @table,
        {{resident_id, session_key},
         Map.merge(p, %{doing: what, tool: detail && Map.get(detail, :name), since: now})}
      )
    end)

    :ok
  end

  @doc "Where the conversation's turn is, or nil when none was seen."
  def of(_resident_id, nil), do: nil

  def of(resident_id, session_key) do
    safely(fn ->
      case :ets.lookup(@table, {resident_id, session_key}) do
        [{_, p}] -> p
        [] -> nil
      end
    end)
  end

  # Absent before the process starts (a script, a test without the app).
  defp safely(fun), do: if(:ets.whereis(@table) == :undefined, do: nil, else: fun.())
end
