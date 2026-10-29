defmodule Oneiroi.HuginnMuninn.NightlyWorker do
  @moduledoc """
  The nightly audit run (spec §6.13): every audit for every active
  resident, after the judgement pass. A cross-tenant job under the
  platform scope, named here (huginn-muninn #12); the roster is the
  resident system's platform-scoped export.
  """
  use Oneiroi.Worker, queue: :huginn_muninn_nightly

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.HuginnMuninn.Checks

  @actor Actor.new(:job, "huginn_muninn_nightly")

  def run(_args) do
    for row <- AgathosDaimon.active_residents(), do: Checks.run(row.id, @actor)
    :ok
  end
end
