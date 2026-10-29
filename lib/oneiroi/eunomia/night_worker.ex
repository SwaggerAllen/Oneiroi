defmodule Oneiroi.Eunomia.NightWorker do
  @moduledoc """
  The nightly pass (spec §6.4): for every active resident, yesterday in
  the resident's zone, judged once. A cross-tenant job under the platform
  scope, named here (eunomia #19); the roster is read through the
  resident system's own platform-scoped export, never this system's
  process scope.
  """
  use Oneiroi.Worker, queue: :eunomia_nightly

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia.Judgements

  @actor Actor.new(:job, "eunomia_night")

  def run(_args) do
    for row <- AgathosDaimon.active_residents() do
      day =
        Clock.now()
        |> DateTime.shift_zone!(row.timezone || "Etc/UTC")
        |> DateTime.to_date()
        |> Date.add(-1)
        |> Date.to_iso8601()

      Judgements.judge_night(row.id, day, @actor)
    end

    :ok
  end
end
