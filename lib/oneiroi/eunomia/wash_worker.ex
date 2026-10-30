defmodule Oneiroi.Eunomia.WashWorker do
  @moduledoc """
  The weekly wash pass (spec §6.13, P18), after the memory audit, for
  every active resident. A cross-tenant job under the platform scope,
  named here (eunomia #19); the roster is the resident system's
  platform-scoped export.
  """
  use Oneiroi.Worker, queue: :eunomia_weekly

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Eunomia.Wash

  @actor Actor.new(:job, "eunomia_wash")

  def run(_args) do
    for row <- AgathosDaimon.active_residents(), do: Wash.run(row.id, @actor)
    :ok
  end
end
