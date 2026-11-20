defmodule Oneiroi.Seshat.Household.Wakes do
  @moduledoc """
  House check-ins (gaia#41, seshat#75) and the house wake: a check-in's
  thread, every resident woken with a note of its own, and the wake's
  manifest.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Files
  alias Oneiroi.Seshat.HouseholdRounds
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Sunna

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}
  @trunk "trunk.md"
  @house_wake_worker :"Elixir.Oneiroi.Seshat.HouseholdTurnWorker"

  @doc false
  def checkin_answer?(%Actor{kind: :resident, id: id}, %{trunk: %{meta: meta}, replies: replies}),
    do: is_binary(meta["checkin"]) and not Enum.any?(replies, &(&1.meta["by_id"] == id))

  def checkin_answer?(_actor, _thread), do: false

  @doc false
  def open_checkin(household_id, key, label, day) do
    with {:ok, view} <- Core.provision(household_id) do
      thread = "threads/checkin-#{day}-#{key}"
      path = Path.join(thread, @trunk)

      if Files.has?(view, path),
        do: {:ok, thread},
        else: write_checkin(household_id, view, thread, key, label, day)
    end
  end

  defp write_checkin(household_id, _view, thread, key, label, day) do
    path = Path.join(thread, @trunk)

    meta = [
      {"title", "#{label}, #{day}"},
      {"by", @platform.name},
      {"by_kind", "platform"},
      {"posted_at", Files.iso(Clock.now())},
      {"checkin", key}
    ]

    # What holds the talk after is the house's mode (seshat#93; Scarlett's
    # report #20: a round-robin house still told to wait on the beats).
    then_line =
      if HouseholdRounds.on?(household_id),
        do:
          "after your answers the thread's round-robin turns hold the talk, one of you at a time.",
        else:
          "your witness's reply wakes you all, and from there the household's beats hold the talk."

    body =
      "The house checks in: #{label}. Each of you answers here, once, in your own words; " <>
        then_line

    Files.locked(household_id, fn view ->
      changes = [
        {:create, path, Files.render(meta, body)} | Core.descriptor(view, Kinds.named("thread"))
      ]

      case Files.commit(view, changes, "House check-in: #{label}, #{day}", @platform) do
        {:ok, _} -> {:ok, thread}
        # Opened already, by a tick on another node: the same thread.
        {:error, %{kind: :sima_qian_repos_conflict}} -> {:ok, thread}
        other -> other
      end
    end)
  end

  @doc false
  def wake_house(household_id, note_for, thread \\ nil) do
    for %{kind: "resident", id: id} <- Gaia.household_members(household_id),
        not AgathosDaimon.held?(id) do
      # Its manifest first (sunna#71): a check-in's wake carries the thread.
      wake_id = manifest(id, "checkin", [%{kind: "post", thread: thread}], household_id)

      Jobs.enqueue(@house_wake_worker, %{
        "household_id" => household_id,
        "house_wake" => id,
        "note" => note_for.(id),
        "thread" => thread,
        "wake_id" => wake_id
      })
    end
  end

  @doc false
  # A wake's manifest (sunna#71): its id, or nil when it could not be
  # written, which never stops the wake itself.
  def manifest(resident_id, channel, causes, household_id, opts \\ []) do
    case Sunna.manifest_wake(
           resident_id,
           channel,
           causes,
           [household_id: household_id] ++ opts
         ) do
      {:ok, wake_id} -> wake_id
      {:error, _} -> nil
    end
  end

  @doc false
  # The witness's reply in a check-in thread wakes the whole house; after
  # it the beats and the watch hold the talk (the witness, 2026-11-16).
  def wake_house_on_witness(
        household_id,
        thread,
        %{trunk: %{meta: %{"checkin" => _}}} = t,
        written,
        %Actor{kind: :witness}
      ) do
    # Under round-robin threads (seshat#93) the reply starts the thread's
    # rounds, and its turns wake one resident at a time; nobody else here.
    if HouseholdRounds.on?(household_id),
      do: :ok,
      else: wake_all_on_witness(household_id, thread, t, written)
  end

  def wake_house_on_witness(_household_id, _thread, _t, _written, _actor), do: :ok

  defp wake_all_on_witness(household_id, thread, t, written) do
    title = t.trunk.meta["title"]

    wake_house(
      household_id,
      fn _id ->
        "Your witness replied in the house check-in thread #{thread} (\"#{title}\"), reply ##{written.number}. " <>
          "household_read with that path reads it. To answer again, register for a beat (household_register) " <>
          "or watch the thread (household_watch): the beats hold the talk from here. " <>
          Core.post_line()
      end,
      thread
    )
  end
end
