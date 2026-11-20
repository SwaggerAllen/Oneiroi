defmodule Oneiroi.Seshat.HouseholdTurnWorker do
  @moduledoc """
  A household turn's wake, or a beat's digest (seshat#70): enqueued by the
  beats' minute when a turn fires or a beat closes. A turn wakes its
  resident's Oneiroi chat (sunna#51), ends with the wake, and fires the
  next; a digest wakes a resident whose profile is every_beat. Run once:
  a wake is a paid turn, so a job orphaned mid-run is not retried, and a
  turn ended already wakes nobody. Each wake marks its resident as
  working in the house while it runs, in the thread it names (seshat#90).
  """
  use Oneiroi.Worker, queue: :seshat_household_turns, max_attempts: 1

  alias Oneiroi.Seshat.Household
  alias Oneiroi.Seshat.HouseholdBeats
  alias Oneiroi.Seshat.HouseholdRounds
  alias Oneiroi.Seshat.HouseWorking

  # A house check-in's wake, the witness's reply in one (seshat#75), or a
  # mention (seshat#86).
  def run(%{"house_wake" => resident_id, "note" => note} = args) do
    HouseWorking.during(args["household_id"], resident_id, args["thread"], fn ->
      case Oneiroi.Sunna.wake_for_house(
             resident_id,
             note,
             Oneiroi.Actor.new(:job, "house_checkins"),
             args["wake_id"]
           ) do
        {:ok, :woken} -> :ok
        {:error, _} = declined -> declined
      end
    end)
  end

  # A round-robin turn's wake and its expiry (seshat#89).
  def run(%{"household_id" => household_id, "round_turn" => turn_id} = args) do
    turn = Oneiroi.Gaia.round_turn(household_id, turn_id)

    HouseWorking.during(household_id, turn && turn.resident_id, turn && turn.thread, fn ->
      case HouseholdRounds.run_turn(household_id, turn_id, args["wake_id"]) do
        {:answered, turn, text} -> post_answer(household_id, turn, text)
        other -> other
      end
    end)
  end

  def run(%{"household_id" => household_id, "round_expire" => turn_id}),
    do: HouseholdRounds.expire(household_id, turn_id)

  def run(%{"household_id" => household_id, "turn" => turn}) do
    t = Oneiroi.Gaia.household_turn(household_id, turn)

    HouseWorking.during(household_id, t && t.resident_id, nil, fn ->
      HouseholdBeats.run_turn(household_id, turn)
    end)
  end

  def run(%{"household_id" => household_id, "digest" => resident_id, "beat_top" => top}) do
    {:ok, at, _} = DateTime.from_iso8601(top)

    HouseWorking.during(household_id, resident_id, nil, fn ->
      HouseholdBeats.run_digest(household_id, resident_id, at)
    end)
  end

  # Her turn's answer is her reply (seshat#94): posted under her name,
  # spending the token, as household_reply would have. A post refused (the
  # quota, Scarlett's report #21) is never silence: the turn stays live to
  # its window and she is told, her words with it.
  defp post_answer(household_id, turn, text) do
    with {:ok, _decision} <- answer_allowed(household_id, turn),
         {:ok, _} <-
           Household.reply(Oneiroi.Actor.new(:resident, turn.resident_id), turn.thread, %{
             "content" => text
           }) do
      HouseholdRounds.settle(household_id, turn.turn_id)
    else
      {:error, error} -> Household.answer_refused(turn, text, error)
    end
  end

  # Her answer goes to the house: what her chat's turn saw is asked first
  # (kumbukumbu#80); a refusal comes back to her with her words.
  defp answer_allowed(household_id, turn) do
    with {:ok, %{account_id: account}} when is_binary(account) <-
           Oneiroi.AgathosDaimon.fetch(turn.resident_id),
         {:ok, key} <-
           Oneiroi.Kumbukumbu.main_session(turn.resident_id, account, Oneiroi.Actor.platform()) do
      Oneiroi.Kumbukumbu.delivery_check(
        turn.resident_id,
        key,
        nil,
        Oneiroi.Kumbukumbu.audience("household", household_id)
      )
    else
      _no_chat -> {:ok, :no_chat}
    end
  end
end
