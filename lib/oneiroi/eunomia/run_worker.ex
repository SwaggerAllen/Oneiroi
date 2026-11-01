defmodule Oneiroi.Eunomia.RunWorker do
  @moduledoc """
  A regression run's answering, off the witness's request (eunomia #30):
  every model x trial of the run, each card broadcast as it is recorded,
  then the run's end. Enqueued by the `run/4` export once `StartRun` is
  recorded. A per-resident job taking the platform scope by
  `Oneiroi.Worker`'s construction; its reads take the resident's scope
  by name (`Regression.answer_run/3`).
  """
  use Oneiroi.Worker, queue: :eunomia_regression

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Eunomia.Regression

  def run(%{"resident_id" => resident_id, "run_ref" => ref, "actor" => actor}),
    do: Regression.answer_run(resident_id, ref, Actor.from_map(actor))

  @doc """
  Enqueues the answering of a started run.

  An Oban job rather than a task (eunomia #30): the row outlives the
  request and the node, the queue bounds how many runs spend at once,
  and the trace rides the args (`Apsu.Jobs`). One attempt, because a
  second would answer again on the witness's key; a run that stops is
  recorded failed and its recorded cards kept, and the witness starts
  another. Unique on the run, so a doubled insert is one job. If the
  insert is refused the run was started with nothing to answer it, so
  it is failed here rather than left running.
  """
  @spec enqueue(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def enqueue(resident_id, ref, %Actor{} = actor) do
    args = %{"resident_id" => resident_id, "run_ref" => ref, "actor" => Map.from_struct(actor)}

    case Jobs.enqueue(__MODULE__, args,
           max_attempts: 1,
           unique: [period: :infinity, keys: [:resident_id, :run_ref]]
         ) do
      {:ok, _job} ->
        :ok

      {:error, refused} ->
        Regression.fail_run(resident_id, ref, refused, actor)
        {:error, refused}
    end
  end
end
