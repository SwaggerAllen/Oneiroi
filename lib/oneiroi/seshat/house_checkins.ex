defmodule Oneiroi.Seshat.HouseCheckins do
  @moduledoc """
  The house check-ins' minute (seshat#75; gaia#41, sunna#65): over every
  household, each check-in due on the household's own clock opens its
  day's thread in the shared workspace, is recorded fired for the day,
  and wakes every resident open to the house at once, each with the
  words the witness set for her on her Rhythm page. Quiet hours do not
  hold it: they keep what reaches the witness, and this is the house's
  own activity (the witness, 2026-11-16).

  Due is the minute of its time or within `@late` minutes after, on a
  day it has not fired: a check-in set after its time today waits for
  tomorrow, as a resident's own does.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Household
  alias Oneiroi.Sunna

  @actor Actor.new(:job, "house_checkins")
  @late 15

  @doc "Every household's minute."
  def tick_all do
    for id <- Gaia.household_ids(), do: tick(id)
    :ok
  end

  @doc "One household's minute: each due check-in fired, once a day."
  def tick(household_id) do
    %{zone: zone, checkins: checkins} = Gaia.house_checkins(household_id)
    local = DateTime.shift_zone!(Clock.now(), zone)
    day = local |> DateTime.to_date() |> Date.to_iso8601()

    for c <- checkins, due?(c, local, day), do: fire(household_id, c, day)
    :ok
  end

  @doc false
  def due?(%{time: time, last_day: last}, local, day) do
    [h, m] = time |> String.split(":") |> Enum.map(&String.to_integer/1)
    minutes = local.hour * 60 + local.minute - (h * 60 + m)
    last != day and minutes >= 0 and minutes <= @late
  end

  defp fire(household_id, c, day) do
    with {:ok, thread} <- Household.open_checkin(household_id, c.key, c.label, day),
         :ok <- Gaia.house_checkin_fired(household_id, c.key, day, thread, @actor) do
      Household.wake_house(household_id, &note(&1, c, day, thread))
    end
  end

  defp note(resident_id, c, day, thread) do
    yours =
      case Sunna.house_prompt(resident_id, c.key) do
        nil -> "Say where your part of the work stands, in a few lines."
        words -> words
      end

    "House check-in: #{c.label}, #{day}. The whole house checks in at once, in the shared workspace's thread #{thread}. " <>
      "Your part: #{yours} Answer there with household_reply, once, in your own words; " <>
      "your answer to a house check-in waits on no turn of the beats."
  end

  # ---- as members read and keep them ----

  @doc "The caller's household's clock and check-ins, each with the day and thread it last opened."
  def list(%Actor{} = actor) do
    with {:ok, id} <- Household.member_household(actor) do
      %{zone: zone, checkins: checkins} = Gaia.house_checkins(id)
      {:ok, %{zone: zone, checkins: Enum.map(checkins, &shape/1)}}
    end
  end

  @doc "The witness sets the workspace's clock."
  def set_clock(%Actor{} = actor, zone) do
    with {:ok, id} <- Household.member_household(actor),
         :ok <- Gaia.set_household_clock(id, to_string(zone || ""), actor),
         do: list(actor)
  end

  @doc "The witness sets a house check-in."
  def set(%Actor{} = actor, key, label, time) do
    with {:ok, id} <- Household.member_household(actor),
         :ok <- Gaia.set_house_checkin(id, key, label, time, actor),
         do: list(actor)
  end

  @doc "The witness removes a house check-in, with a note."
  def remove(%Actor{} = actor, key, note) do
    with {:ok, id} <- Household.member_household(actor),
         :ok <- Gaia.remove_house_checkin(id, key, note, actor),
         do: list(actor)
  end

  defp shape(c),
    do: %{
      key: c.key,
      label: c.label,
      time: c.time,
      last_day: c.last_day,
      last_thread: c.last_thread,
      last_fired_at: c.last_fired_at
    }
end
