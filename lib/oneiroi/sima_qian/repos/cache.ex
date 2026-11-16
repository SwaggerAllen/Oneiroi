defmodule Oneiroi.SimaQian.Repos.Cache do
  @moduledoc """
  File contents by their blob sha (sima-qian#57): a blob's bytes never
  change, so a hit is never stale and nothing is ever invalidated. A
  thread's trunk and replies are written once, so after the first view a
  shelf costs one tree call and no reads. ETS owned by this process, lost
  on restart (the next read fills it again), and cleared whole when it
  passes its bound, which keeps it simple and its memory capped.
  """
  use GenServer

  @table :sima_qian_blobs
  @bound 20_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: :sima_qian_blobs)

  @impl GenServer
  def init(_opts) do
    {:ok, :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])}
  end

  @doc "The bytes of `sha`, or nil."
  def get(sha) do
    case :ets.whereis(@table) != :undefined && :ets.lookup(@table, sha) do
      [{^sha, bytes}] -> bytes
      _miss -> nil
    end
  end

  @doc "Keeps `bytes` under `sha`."
  def put(sha, bytes) do
    if :ets.whereis(@table) != :undefined do
      if :ets.info(@table, :size) >= @bound, do: :ets.delete_all_objects(@table)
      :ets.insert(@table, {sha, bytes})
    end

    :ok
  end
end
