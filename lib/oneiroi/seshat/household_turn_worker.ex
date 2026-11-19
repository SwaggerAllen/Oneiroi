defmodule Oneiroi.Seshat.HouseholdTurnWorker do
  @moduledoc """
  A household turn's wake, or a beat's digest (seshat#70): enqueued by the
  beats' minute when a turn fires or a beat closes. A turn wakes its
  resident's Oneiroi chat (sunna#51), ends with the wake, and fires the
  next; a digest wakes a resident whose profile is every_beat. Run once:
  a wake is a paid turn, so a job orphaned mid-run is not retried, and a
  turn ended already wakes nobody.
  """
  use Oneiroi.Worker, queue: :seshat_household_turns, max_attempts: 1

  alias Oneiroi.Seshat.HouseholdBeats
  alias Oneiroi.Seshat.HouseholdRounds

  # A house check-in's wake, or the witness's reply in one (seshat#75).
  def run(%{"house_wake" => resident_id, "note" => note}) do
    case Oneiroi.Sunna.wake_for_house(
           resident_id,
           note,
           Oneiroi.Actor.new(:job, "house_checkins")
         ) do
      {:ok, :woken} -> :ok
      {:error, _} = declined -> declined
    end
  end

  # A round-robin turn's wake and its expiry (seshat#89).
  def run(%{"household_id" => household_id, "round_turn" => turn_id}),
    do: HouseholdRounds.run_turn(household_id, turn_id)

  def run(%{"household_id" => household_id, "round_expire" => turn_id}),
    do: HouseholdRounds.expire(household_id, turn_id)

  def run(%{"household_id" => household_id, "turn" => turn}),
    do: HouseholdBeats.run_turn(household_id, turn)

  def run(%{"household_id" => household_id, "digest" => resident_id, "beat_top" => top}) do
    {:ok, at, _} = DateTime.from_iso8601(top)
    HouseholdBeats.run_digest(household_id, resident_id, at)
  end
end
