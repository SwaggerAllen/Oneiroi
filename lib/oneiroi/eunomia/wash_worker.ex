defmodule Oneiroi.Eunomia.WashWorker do
  @moduledoc """
  The weekly wash pass (spec §6.13, P18), after the memory audit, for
  every active resident. A cross-tenant job under the platform scope,
  named here (eunomia #19); the roster is the resident system's
  platform-scoped export.
  """
  # One attempt (eunomia #30): the pass calls the judge for every
  # resident and keeps no once-a-week mark, so a retry, after a crash or
  # after Lifeline rescues an orphan, would judge the residents already
  # done again, on their witnesses' keys, and raise their flags twice.
  # An interrupted week is discarded and the next week runs.
  use Oneiroi.Worker, queue: :eunomia_weekly, max_attempts: 1

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Eunomia.Wash

  @actor Actor.new(:job, "eunomia_wash")

  def run(_args) do
    for row <- AgathosDaimon.active_residents(), do: Wash.run(row.id, @actor)
    :ok
  end
end
