defmodule Oneiroi.Seshat.HouseholdBeatWorker do
  @moduledoc """
  The household beats' minute (seshat#70): over every household, since
  every household runs on beats (gaia#33), its aggregate times out a turn
  past its guideline, closes the beats that ended and fires the next turn
  when one is due. A cross-tenant job under the platform scope.
  Replay-safe: each outcome is an event the household's aggregate takes
  once, so two runs on one minute fire once.
  """
  use Oneiroi.Worker, queue: :seshat_household_beats, unique: [period: 30]

  alias Oneiroi.Seshat.HouseholdBeats

  def run(_args), do: HouseholdBeats.tick_all()
end
