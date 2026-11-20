defmodule Oneiroi.Gaia.RoundRobin do
  @moduledoc """
  The service over a household's round-robin threads (gaia#53): the
  commands, answered with the events they recorded (so the caller wakes
  whoever a turn was issued to), and the reads.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.RoundsRouter
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc "A thread's rounds begin, or begin again when stopped (or never begun); nothing while they run."
  def start(
        household_id,
        thread,
        residents,
        starter,
        timeout,
        order,
        %Actor{} = actor,
        first \\ []
      ),
      do:
        dispatch(%Commands.StartRounds{
          actor: actor,
          at: Clock.now(),
          id: household_id,
          thread: thread,
          residents: residents,
          starter: starter,
          timeout: timeout,
          order: order,
          first: first
        })

  @doc "Her post or skip in her turn: refused unless her live token for that thread."
  def spend(household_id, thread, resident_id, how, %Actor{} = actor),
    do:
      dispatch(%Commands.SpendTurn{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        thread: thread,
        resident_id: resident_id,
        how: how
      })

  @doc "Ends a turn the platform's way: `empty` (the wake said nothing) or `expired`."
  def end_turn(household_id, turn_id, outcome, %Actor{} = actor),
    do:
      dispatch(%Commands.EndRoundTurn{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        turn_id: turn_id,
        outcome: outcome
      })

  def opt_out(household_id, thread, resident_id, %Actor{} = actor),
    do:
      dispatch(%Commands.OptOutOfRounds{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        thread: thread,
        resident_id: resident_id
      })

  def opt_in(household_id, thread, resident_id, %Actor{} = actor),
    do:
      dispatch(%Commands.OptIntoRounds{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        thread: thread,
        resident_id: resident_id
      })

  @doc "A thread's rounds as read, or nil when they never began."
  def thread(household_id, thread) do
    Scope.platform(fn ->
      Repo.one(
        from(t in Store.RoundThread,
          where: t.household_id == ^household_id and t.thread == ^thread
        )
      )
    end)
  end

  @doc "A turn by its id, or nil."
  def turn(household_id, turn_id) do
    Scope.platform(fn ->
      Repo.one(
        from(t in Store.RoundTurn,
          where: t.household_id == ^household_id and t.turn_id == ^turn_id
        )
      )
    end)
  end

  @doc "The turns of the house, newest first: the visible queue (issued, until, spent how)."
  def turns(household_id, limit \\ 50) do
    Scope.platform(fn ->
      Repo.all(
        from(t in Store.RoundTurn,
          where: t.household_id == ^household_id,
          order_by: [desc: t.issued_at],
          limit: ^limit
        )
      )
    end)
  end

  @doc "Every turn, any house, still live past its window: what the sweep ends (gaia#55)."
  def overdue(%DateTime{} = now) do
    Scope.platform(fn ->
      Repo.all(
        from(t in Store.RoundTurn,
          where: is_nil(t.outcome) and t.expires_at <= ^now,
          order_by: [asc: t.expires_at],
          select: %{household_id: t.household_id, turn_id: t.turn_id}
        )
      )
    end)
  end

  @doc "Every thread's rounds in a house, latest changed first (gaia#55): the thread states."
  def threads(household_id) do
    Scope.platform(fn ->
      Repo.all(
        from(t in Store.RoundThread,
          where: t.household_id == ^household_id,
          order_by: [desc: t.changed_at]
        )
      )
    end)
  end

  defp dispatch(command) do
    case RoundsRouter.dispatch(command) do
      {:ok, events} when is_list(events) ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_rounds_failed, :gaia_rounds_dispatch, reason)}
    end
  end
end
