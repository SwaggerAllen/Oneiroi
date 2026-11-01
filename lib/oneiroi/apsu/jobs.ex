defmodule Oneiroi.Apsu.Jobs do
  @moduledoc """
  The one door to Oban's insert surface (conventions §7, §10): an enqueue
  carries the current trace id into the job's args so the worker's log
  lines join the request's, and nothing outside this module calls
  `Oban.insert/1`, which the boundary declarations hold. It is the one
  reader of a job's state too (`states/2`), so no system names Oban's
  table.
  """
  require Logger

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Error

  @doc "Enqueues `worker` with `args`, carrying the trace id; Oban's refusal is wrapped here, once."
  @spec enqueue(module(), map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, Error.t()}
  def enqueue(worker, args, opts \\ []) when is_atom(worker) and is_map(args) do
    inserted =
      args
      |> Map.put("trace_id", Keyword.get(Logger.metadata(), :trace_id))
      |> worker.new(opts)
      |> Oban.insert()

    case inserted do
      {:ok, job} ->
        {:ok, job}

      {:error, reason} ->
        {:error, Error.caught(:apsu_enqueue_failed, :apsu_jobs_insert_refused, reason)}
    end
  end

  @doc """
  The states of `worker`'s jobs whose args contain `args` (Postgres
  `@>`), newest first; `[]` when there is none, which includes a job the
  pruner has removed. Called under the caller's scope; Oban's table has
  no tenant column, so any scope reads it.
  """
  @spec states(module(), map()) :: [String.t()]
  def states(worker, args) when is_atom(worker) and is_map(args) do
    name = worker |> Module.split() |> Enum.join(".")

    Oneiroi.Repo.all(
      from(j in Oban.Job,
        where: j.worker == ^name and fragment("? @> ?", j.args, ^args),
        order_by: [desc: j.id],
        select: j.state
      )
    )
  end
end
