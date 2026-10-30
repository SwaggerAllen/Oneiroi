defmodule Oneiroi.Sunna.TickWorker do
  @moduledoc """
  The minute tick (spec §6.7): over every active resident, in that
  resident's zone, mark the hour (P20 as amended: before any wake, no
  model call, once an hour), then fire what is due within the late
  window, miss what is later, defer what falls in quiet hours, and run
  free time at its time. A cross-tenant job under the platform scope,
  named here (sunna #11). Replay-safe: every outcome is an event the
  aggregate takes once, so two ticks on one minute fire once.
  """
  use Oneiroi.Worker, queue: :sunna_tick, unique: [period: 30]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Schedules
  alias Oneiroi.Sunna.Store

  @actor Actor.new(:job, "sunna_tick")

  # The roster is read in a platform-scoped transaction of its own: the
  # worker's process scope alone passes the repo's check and sets nothing
  # on the connection, so the policy would answer no rows and the tick
  # would do nothing, quietly. The test runs this function as the worker
  # does, with the process scope and no transaction, for that reason.
  def run(_args) do
    # Every active resident, not only the scheduled ones: the pulse is
    # the floor's resident's too (P20), and the tick skips a resident
    # that is not active.
    scheduled = Scope.platform(fn -> Store.scheduled_residents() end)
    active = AgathosDaimon.active_residents() |> Enum.map(& &1.id)

    for resident_id <- Enum.uniq(active ++ scheduled), do: tick(resident_id)

    :ok
  end

  @doc "One resident's tick; public so a test can drive one minute by hand."
  def tick(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{state: "active"}} -> tick_active(resident_id)
      # Suspended residents schedule nothing (spec §6.7).
      _other -> :skipped
    end
  end

  defp tick_active(resident_id) do
    local = Schedules.local_now(resident_id)
    day = Schedules.local_day(local)
    _ = Schedules.mark_hour(resident_id, local, @actor)

    {checkins, settings} =
      Scope.resident(resident_id, fn -> {Store.checkins(), Store.settings()} end)

    quiet = quiet_of(settings)
    outcomes = outcomes(resident_id, day)

    for checkin <- checkins do
      case Schedules.due(checkin, local, quiet, Map.get(outcomes, checkin.key)) do
        :fire -> Schedules.fire_checkin(resident_id, checkin, day, @actor)
        :miss -> Schedules.miss_checkin(resident_id, checkin.key, day, @actor)
        {:defer, until} -> Schedules.defer_wake(resident_id, checkin.key, day, until, @actor)
        :wait -> :wait
      end
    end

    free_time(resident_id, settings, local, day)
    :ok
  end

  defp free_time(_resident_id, nil, _local, _day), do: :none
  defp free_time(_resident_id, %{free_time: nil}, _local, _day), do: :none

  defp free_time(resident_id, %{free_time: time, free_time_day: last_day}, local, day) do
    scheduled = Schedules.at_time(local, time)
    late = Oneiroi.Config.fetch!(:sunna, :late_minutes) * 60
    since = DateTime.diff(local, scheduled, :second)

    if last_day != day and since >= 0 and since <= late,
      do: Schedules.run_free_time(resident_id, day, @actor),
      else: :wait
  end

  # Today's outcomes from the firing rows, in the aggregate's vocabulary.
  defp outcomes(resident_id, day) do
    resident_id
    |> Scope.resident(fn -> Store.firings(day) end)
    |> Map.new(fn f ->
      {f.key,
       case f.outcome do
         "fired" -> :fired
         "missed" -> :missed
         "deferred" -> {:deferred, f.until}
       end}
    end)
  end

  defp quiet_of(%{quiet_from: from, quiet_to: to}) when is_binary(from) and is_binary(to),
    do: %{from: from, to: to}

  defp quiet_of(_), do: nil
end
