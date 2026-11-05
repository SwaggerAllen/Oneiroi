defmodule Oneiroi.Gaia.Households do
  @moduledoc """
  The household's service functions (gaia#17): which household an
  account is in, the household as its members read it, and the terms
  granted to it.

  The household row is platform-scoped, every member's and no one's
  alone, so reading it takes the platform scope by name (conventions
  §12), and only after the caller's own membership row, read under the
  caller's scope, has said which household it is.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.HouseholdRouter
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc """
  The household the account is in: its membership's, or, before the
  projection has one, the account's own id, which is the id of the
  household it founded.
  """
  def household_id(account_id) do
    Scope.account(account_id, fn ->
      Repo.one(
        from(m in Store.HouseholdWitness,
          where: m.account_id == ^account_id,
          order_by: m.joined_at,
          limit: 1,
          select: m.household_id
        )
      )
    end) || account_id
  end

  @doc "The account's household as its members see it: who is in it and its terms, or nil before it is founded."
  def household(account_id) do
    id = household_id(account_id)

    # The named cross-tenant read: the household and its other members'
    # rows, once the caller's own membership has named it.
    Scope.platform(fn ->
      case Repo.get(Store.Household, id) do
        nil -> nil
        row -> shape(row)
      end
    end)
  end

  defp shape(row) do
    witnesses =
      Repo.all(
        from(m in Store.HouseholdWitness,
          where: m.household_id == ^row.id,
          order_by: m.joined_at,
          select: m.account_id
        )
      )

    residents =
      Repo.all(
        from(m in Store.HouseholdResident,
          where: m.household_id == ^row.id,
          order_by: m.joined_at,
          select: m.resident_id
        )
      )

    %{
      id: row.id,
      founded_at: row.founded_at,
      witnesses: witnesses,
      residents: residents,
      terms: terms(row)
    }
  end

  defp terms(%{plan: nil}), do: nil

  defp terms(row),
    do: %{
      plan: row.plan,
      price_nanos: row.price_nanos,
      until: row.terms_until,
      source: row.terms_source,
      note: row.terms_note
    }

  @doc """
  Grants the household terms: a plan, its price, until when, and where
  they came from. The platform's (an invite code redeemed) or a super
  admin's; nothing is charged.
  """
  def grant_terms(household_id, terms, note, %Actor{} = actor) do
    with :ok <- may_grant(actor) do
      dispatch(%Commands.GrantHouseholdTerms{
        actor: actor,
        at: Clock.now(),
        id: household_id,
        plan: terms.plan,
        price_nanos: terms.price_nanos,
        terms_until: terms.until,
        source: terms.source,
        note: note
      })
    end
  end

  defp may_grant(%Actor{kind: :platform}), do: :ok

  defp may_grant(%Actor{kind: :witness, id: id}) do
    if Door.operator?(id),
      do: :ok,
      else: {:error, Error.new(:gaia_not_an_operator, :gaia_household_terms_not_operator)}
  end

  defp may_grant(%Actor{}),
    do: {:error, Error.new(:gaia_not_an_operator, :gaia_household_terms_not_a_witness)}

  defp dispatch(command) do
    case HouseholdRouter.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:gaia_dispatch_failed, :gaia_household_dispatch_failed, reason)}
    end
  end
end
