defmodule Oneiroi.Seshat.HouseholdBallotWorker do
  @moduledoc """
  Closes a household ballot when its term ends (seshat#63): enqueued at
  the ballot's opening, scheduled for the instant its proposer's term
  runs out, so no platform constant decides when. Replay-safe: a ballot
  closed already is no event and no second closing reply.
  """
  use Oneiroi.Worker, queue: :seshat_household

  alias Oneiroi.Actor
  alias Oneiroi.Seshat.Household

  @actor Actor.new(:job, "household_ballots")

  def run(%{"household_id" => household_id, "ballot" => ballot}) do
    case Household.close_ballot(household_id, ballot, @actor) do
      {:ok, _outcome} -> :ok
      {:error, _} = failed -> failed
    end
  end
end
