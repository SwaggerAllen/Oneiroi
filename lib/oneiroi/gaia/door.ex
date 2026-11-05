defmodule Oneiroi.Gaia.Door do
  @moduledoc """
  The front door and its keepers (gaia#16). The gate is `closed` until a
  super admin opens it (to `invite` or `open`); the founding account,
  the first ever created, is granted super admin by the platform the
  first time the door is asked about, as an event anyone can read, so
  the operator is a recorded grant and never inferred from account age.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.PlatformRouter
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc """
  The platform stream's id: `platform`. The suite gives each test a stream
  of its own (`Process.put(Oneiroi.Gaia.Door, id)`), because the event
  store is not rolled back between tests as the projections are, and a
  stream every test shared would carry one test's keeper into the next.
  """
  def stream, do: Process.get(__MODULE__, "platform")

  @doc "The gate: closed, invite or open, and when and by whom it was set."
  def gate do
    Scope.platform(fn -> Repo.get(Store.Gate, "door") end)
    |> case do
      nil -> %{state: "closed", note: nil, set_by: nil, set_at: nil}
      row -> Map.take(row, [:state, :note, :set_by, :set_at])
    end
  end

  @doc "Every role held, oldest first."
  def roles do
    ensure_founder()
    Scope.platform(fn -> Repo.all(from(r in Store.Role, order_by: r.granted_at)) end)
  end

  @doc "The roles one account holds."
  def roles_of(account_id), do: for(r <- roles(), r.account_id == account_id, do: r.role)

  @doc "Whether the account is a super admin, the operator."
  def operator?(account_id), do: "super_admin" in roles_of(account_id)

  def set_gate(state, note, %Actor{} = actor),
    do:
      dispatch(%Commands.SetGate{
        actor: actor,
        at: Clock.now(),
        id: stream(),
        state: state,
        note: note
      })

  def grant(account_id, role, note, %Actor{} = actor),
    do:
      dispatch(%Commands.GrantRole{
        actor: actor,
        at: Clock.now(),
        id: stream(),
        account_id: account_id,
        role: role,
        note: note
      })

  def revoke(account_id, role, note, %Actor{} = actor),
    do:
      dispatch(%Commands.RevokeRole{
        actor: actor,
        at: Clock.now(),
        id: stream(),
        account_id: account_id,
        role: role,
        note: note
      })

  # The founding account's grant, recorded once by the platform while no
  # super admin exists (the aggregate refuses it otherwise).
  defp ensure_founder do
    held? =
      Scope.platform(fn ->
        Repo.exists?(from(r in Store.Role, where: r.role == "super_admin"))
      end)

    with false <- held?,
         %{id: founder} <-
           Scope.platform(fn ->
             Repo.one(from(a in Store.Account, order_by: a.created_at, limit: 1))
           end) do
      _ =
        grant(
          founder,
          "super_admin",
          "the founding account: the first witness is the operator",
          Actor.platform()
        )
    end

    :ok
  end

  defp dispatch(command) do
    case PlatformRouter.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_dispatch_failed, :gaia_door_dispatch_failed, reason)}
    end
  end
end
