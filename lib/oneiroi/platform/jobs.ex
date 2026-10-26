defmodule Oneiroi.Platform.Jobs do
  @moduledoc """
  The one door to Oban's insert surface (conventions §7, §10): an enqueue
  carries the current trace id into the job's args so the worker's log
  lines join the request's, and nothing outside this module calls
  `Oban.insert/1`, which the boundary declarations hold.
  """
  require Logger

  @doc "Enqueues `worker` with `args`, carrying the trace id."
  @spec enqueue(module(), map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(worker, args, opts \\ []) when is_atom(worker) and is_map(args) do
    args
    |> Map.put("trace_id", Keyword.get(Logger.metadata(), :trace_id))
    |> worker.new(opts)
    |> Oban.insert()
  end
end
