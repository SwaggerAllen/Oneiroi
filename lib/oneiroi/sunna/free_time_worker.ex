defmodule Oneiroi.Sunna.FreeTimeWorker do
  @moduledoc """
  Free time carried on (sunna#26): a free-time pass that ran out of
  tool rounds is woken again in its own conversation, one turn a job, so
  a long pass never holds the minute tick that fires everyone's
  check-ins. It goes on while the witness's free-time budget line has
  money left this period, up to `SUNNA_FREE_TIME_TURNS` turns a slot,
  and stops when a turn ends in words with nothing left to call: her
  saying she is done.
  """
  use Oneiroi.Worker, queue: :sunna_free_time, max_attempts: 1

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Sunna.Schedules

  def run(%{"resident_id" => id, "turn" => "scene", "day" => day, "slot" => slot} = args),
    do: Schedules.scene_pass(id, day, slot, args["session_key"], args["n"] || 1)

  def run(%{"resident_id" => id, "turn" => pass, "day" => day, "slot" => slot} = args)
      when pass in ["people", "behaviour", "presence"],
      do: Schedules.night_pass(id, pass, day, slot, args["session_key"], args["n"] || 1)

  def run(%{"resident_id" => resident_id, "session_key" => key, "turn" => "plan"}),
    do: Schedules.plan_free_time(resident_id, key)

  def run(%{"resident_id" => resident_id, "session_key" => key, "turn" => n} = args),
    do: Schedules.continue_free_time(resident_id, key, n, args["run"])

  @doc "Enqueues turn `n` of the bedtime scene pass before `slot` (sunna#34), once a day a turn."
  def enqueue_scene(resident_id, day, slot, key, n) do
    Jobs.enqueue(
      __MODULE__,
      %{
        "resident_id" => resident_id,
        "turn" => "scene",
        "day" => day,
        "slot" => slot,
        "session_key" => key,
        "n" => n
      },
      unique: [period: :infinity, keys: [:resident_id, :turn, :day, :n]]
    )
  end

  @doc "Enqueues turn `n` of a night pass after the scene pass (sunna#57), once a day a turn."
  def enqueue_night(resident_id, pass, day, slot, key, n) do
    Jobs.enqueue(
      __MODULE__,
      %{
        "resident_id" => resident_id,
        "turn" => pass,
        "day" => day,
        "slot" => slot,
        "session_key" => key,
        "n" => n
      },
      unique: [period: :infinity, keys: [:resident_id, :turn, :day, :n]]
    )
  end

  @doc "Enqueues a run's planning turn (sunna#31), once per run of the conversation (sunna#69)."
  def enqueue_plan(resident_id, key, run \\ nil), do: enqueue(resident_id, key, "plan", run)

  @doc """
  Enqueues turn `n` of the free-time pass in `key`, once per run
  (sunna#69): a slot's run, or a letter's wake resuming the same
  conversation later, each with its own turns and planning turn.
  """
  def enqueue(resident_id, key, n, run \\ nil) do
    Jobs.enqueue(
      __MODULE__,
      %{"resident_id" => resident_id, "session_key" => key, "turn" => n, "run" => run},
      unique: [period: :infinity, keys: [:session_key, :run, :turn]]
    )
  end
end
