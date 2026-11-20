defmodule Oneiroi.Seshat.Household.Rounds do
  @moduledoc """
  Round-robin threads (seshat#89) and a witness's notices from the
  house: a thread's round settings, the pushes, the unread count and
  the read mark.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.Household.Gate
  alias Oneiroi.Seshat.HouseholdRounds

  @doc false
  def rounds(%Actor{kind: :resident} = actor, thread_name, what)
      when what in [:skip, :out, :in] do
    with {:ok, household_id} <- Core.household(actor),
         :ok <- rounds_on(household_id),
         thread when is_binary(thread) <-
           Files.thread_path(thread_name) || Files.no_thread(thread_name),
         {:ok, r} <- rounds_step(actor, household_id, thread, what) do
      {:ok, %{thread: thread, rounds: r}}
    end
  end

  def rounds(%Actor{}, _thread_name, _what),
    do: {:error, Error.new(:seshat_household_rounds, :seshat_household_rounds_resident)}

  defp rounds_step(actor, household_id, thread, :skip),
    do: HouseholdRounds.skip(actor, household_id, thread)

  defp rounds_step(actor, household_id, thread, what),
    do: HouseholdRounds.opt(actor, household_id, thread, what == :out)

  defp rounds_on(household_id) do
    if HouseholdRounds.on?(household_id),
      do: :ok,
      else: {:error, Error.new(:seshat_household_rounds, :seshat_household_rounds_off)}
  end

  @doc false
  def pushes(%Actor{kind: :witness} = actor) do
    with {:ok, household_id} <- Core.household(actor),
         do: {:ok, Gaia.household_pushes(household_id, actor.id)}
  end

  def pushes(%Actor{}),
    do: {:error, Error.new(:seshat_household_residents_write, :seshat_household_pushes_witness)}

  @doc false
  def set_push(%Actor{kind: :witness} = actor, kind, on) do
    with {:ok, household_id} <- Core.household(actor),
         :ok <- Gaia.set_household_push(household_id, to_string(kind || ""), on, actor),
         do: {:ok, Gaia.household_pushes(household_id, actor.id)}
  end

  def set_push(%Actor{}, _kind, _on),
    do: {:error, Error.new(:seshat_household_residents_write, :seshat_household_set_push_witness)}

  @doc false
  def unread(%Actor{kind: :witness} = actor) do
    with {:ok, household_id} <- Core.household(actor),
         {:ok, view} <- Core.provision(household_id) do
      subject = "house:" <> household_id
      marks = Gaia.seen(actor.id, subject)
      baseline = Map.get(marks, "*") || set_baseline(actor, subject)

      mark = &later(Map.get(marks, &1), baseline)

      threads =
        for w <- Gate.writes(view),
            w.kind in ["thread", "reply"],
            w.by_id != actor.id,
            DateTime.compare(w.at, mark.(w.target)) == :gt,
            reduce: %{},
            do: (acc -> Map.update(acc, w.target, 1, &(&1 + 1)))

      # Where each thread with unread was read up to: a thread opens at
      # the first post after it (seshat#97).
      seen = Map.new(threads, fn {path, _n} -> {path, mark.(path)} end)

      {:ok, %{count: threads |> Map.values() |> Enum.sum(), threads: threads, seen: seen}}
    end
  end

  def unread(%Actor{}), do: {:ok, %{count: 0, threads: %{}, seen: %{}}}

  # A first look: everything before now counts as seen.
  defp set_baseline(actor, subject) do
    now = Clock.now()
    _ = Gaia.mark_seen(actor.id, subject, "*", now, actor)
    now
  end

  defp later(nil, b), do: b

  defp later(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  @doc false
  def mark_seen(%Actor{kind: :witness} = actor, thread, %DateTime{} = at) do
    with {:ok, household_id} <- Core.household(actor),
         path when is_binary(path) <- Files.thread_path(thread) || Files.no_thread(thread),
         do: Gaia.mark_seen(actor.id, "house:" <> household_id, path, at, actor)
  end

  def mark_seen(%Actor{}, _thread, _at), do: :ok
end
