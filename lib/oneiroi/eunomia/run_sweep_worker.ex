defmodule Oneiroi.Eunomia.RunSweepWorker do
  @moduledoc """
  The sweep for regression runs whose job is gone (eunomia #30). A
  cross-tenant job under the platform scope, named here: it reads every
  running run and each one's job state, and fails the abandoned ones
  through `Regression.fail_run/4`, which broadcasts the end so an open
  screen updates.

  Cron fires it every minute and it acts on the minutes that
  `EUNOMIA_RUN_SWEEP_MINUTES` divides. The cadence is a setting, and a
  crontab is a declaration the composer and the audit read before any
  setting is loaded, so the schedule cannot be built from it; the
  minute that does nothing costs one job row, as the minute tick does.
  Replay-safe: failing an ended run is a no-op on the aggregate.

  The sweep is here rather than in `Regression` because it names
  `RunWorker`, which calls `Regression`; xref counts that as a cycle.
  """
  use Oneiroi.Worker, queue: :eunomia_regression, unique: [period: 30]

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Config
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Regression
  alias Oneiroi.Eunomia.RunWorker
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Scope

  @actor Actor.new(:job, "eunomia_run_sweep")

  # The states in which a run's job may still answer it. A run whose job
  # is in one of them is never touched.
  @live ~w(available scheduled executing retryable)

  def run(_args) do
    if due?(Clock.now()), do: sweep(@actor)
    :ok
  end

  @doc "Whether the sweep acts at `now`: on the minutes the setting divides, counted from midnight UTC."
  @spec due?(DateTime.t()) :: boolean()
  def due?(%DateTime{} = now) do
    every = max(Config.fetch!(:eunomia, :run_sweep_minutes), 1)
    rem(now.hour * 60 + now.minute, every) == 0
  end

  @doc """
  Fails every run still running whose answering job is no longer live:
  `completed`, `discarded` or `cancelled`, or no job at all. A node that
  stops mid-run leaves its job `executing` until Lifeline rescues it; a
  run worker has one attempt, so the rescue discards it and the next
  sweep fails the run. A run started within the last minute is left:
  `run/4` records the start and then inserts the job, and a sweep landing
  between the two would find no job yet. The minute is a bound on two
  statements in one request, not measured. Returns the refs it failed.
  """
  @spec sweep(Actor.t()) :: [String.t()]
  def sweep(%Actor{} = actor) do
    cutoff = DateTime.add(Clock.now(), -60, :second)

    for run <- Scope.platform(fn -> Store.running_runs() end),
        DateTime.compare(run.started_at, cutoff) == :lt,
        states = job_states(run),
        not Enum.any?(states, &(&1 in @live)) do
      # The cause is the run's state, abandoned, and the job's state (or
      # "gone") rides the details for the log line.
      error =
        Error.caught(:eunomia_run_abandoned, :eunomia_run_sweep_abandoned, :abandoned,
          job: List.first(states, "gone")
        )

      Logger.warning(
        "eunomia: a regression run's job is gone; the run is failed",
        Oneiroi.Error.metadata(error)
      )

      Regression.fail_run(run.resident_id, run.ref, error, actor)
      run.ref
    end
  end

  defp job_states(run) do
    Scope.platform(fn ->
      Jobs.states(RunWorker, %{"resident_id" => run.resident_id, "run_ref" => run.ref})
    end)
  end
end
