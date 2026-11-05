defmodule Oneiroi.Sunna.TickWorker do
  @moduledoc """
  The minute tick (spec §6.7): over every active resident, in that
  resident's zone, mark the hour (P20 as amended: before any wake, no
  model call, once an hour), then fire what is due within the late
  window, miss what is later, defer what falls in quiet hours, and run
  free time at its time. A cross-tenant job under the platform scope,
  named here (sunna#11). Replay-safe: every outcome is an event the
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
    rounds(resident_id, quiet, local, day)
    _ = Schedules.wake_for_letters(resident_id, local, quiet, @actor)
    :ok
  end

  # Every resident has free time, at the slots set or the default
  # (sunna#21, #22), so a resident nobody configured still gets it. A
  # slot runs once a day; a day recorded before slots (slot nil) had its
  # one free time and runs no other.
  # A slot has run when a run was recorded at or after its instant
  # (sunna#27), not when a run carries its label: a change of zone gives a
  # later slot the label of an earlier run, and the label once swallowed
  # it. A day recorded before slots (slot nil) still had its one.
  defp free_time(resident_id, settings, local, day) do
    ran = Scope.resident(resident_id, fn -> Schedules.free_time_ran(settings, day) end)
    recent = Scope.resident(resident_id, fn -> Store.free_time_history(8) end)
    late = Oneiroi.Config.fetch!(:sunna, :late_minutes) * 60

    for time <- Schedules.free_times_of(settings),
        not Map.has_key?(ran, nil),
        slot = Schedules.at_time(local, time),
        not Enum.any?(recent, &(DateTime.compare(&1.at, slot) != :lt)),
        since = DateTime.diff(local, slot, :second),
        since >= 0 and since <= late do
      Schedules.run_free_time(resident_id, day, time, @actor)
    end

    :ok
  end

  # The day's thinking rounds (sunna#29), each run once when its drawn
  # time has come and the late window has not passed; a missed one is
  # simply not had, as a missed chance is.
  defp rounds(resident_id, quiet, local, day) do
    late = Oneiroi.Config.fetch!(:sunna, :late_minutes) * 60

    for time <- Schedules.round_times(resident_id, day, quiet),
        since = DateTime.diff(local, Schedules.at_time(local, time), :second),
        since >= 0 and since <= late,
        not Schedules.quiet?(local, quiet) do
      Schedules.run_round(resident_id, day, time, @actor)
    end

    :ok
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
