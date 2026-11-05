defmodule Oneiroi.Gaia.Household do
  @moduledoc """
  The household aggregate (gaia#17), on `household-<id>`: the billing
  owner from day one, with two kinds of membership hanging off it, its
  witnesses and its residents. A solo witness with one resident is a
  household of one pair, the same shape, never a special case.

  Founded once, by the platform, when its founding account is created;
  the id is that account's. Every account and every resident sits in a
  household from creation ("never neither"): a household with no terms
  is still the place terms will land. Memberships are idempotent, so a
  replay is harmless; a resident leaves only with a note.
  """

  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct [:id, witnesses: MapSet.new(), residents: MapSet.new(), terms: nil]

  @plan_limit 60

  def execute(%__MODULE__{id: nil}, %Commands.FoundHousehold{} = c) do
    if is_binary(c.account_id),
      do: %Events.HouseholdFounded{actor: c.actor, at: c.at, id: c.id, account_id: c.account_id},
      else: {:error, Error.new(:gaia_household_invalid, :gaia_household_found_no_account)}
  end

  def execute(%__MODULE__{}, %Commands.FoundHousehold{}), do: []

  def execute(%__MODULE__{id: nil}, _command),
    do: {:error, Error.new(:gaia_no_such_household, :gaia_household_not_founded)}

  def execute(%__MODULE__{witnesses: w}, %Commands.JoinHouseholdWitness{} = c) do
    if MapSet.member?(w, c.account_id),
      do: [],
      else: %Events.HouseholdWitnessJoined{
        actor: c.actor,
        at: c.at,
        id: c.id,
        account_id: c.account_id
      }
  end

  def execute(%__MODULE__{residents: r}, %Commands.JoinHouseholdResident{} = c) do
    if MapSet.member?(r, c.resident_id),
      do: [],
      else: %Events.HouseholdResidentJoined{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id
      }
  end

  def execute(%__MODULE__{residents: r}, %Commands.LeaveHouseholdResident{} = c) do
    if MapSet.member?(r, c.resident_id),
      do: %Events.HouseholdResidentLeft{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id,
        note: c.note
      },
      else: []
  end

  def execute(%__MODULE__{}, %Commands.GrantHouseholdTerms{} = c) do
    if terms_ok?(c),
      do: %Events.HouseholdTermsGranted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        plan: c.plan,
        price_nanos: c.price_nanos,
        terms_until: c.terms_until,
        source: c.source,
        note: c.note
      },
      else: {:error, Error.new(:gaia_household_invalid, :gaia_household_terms_invalid)}
  end

  def apply(%__MODULE__{} = h, %Events.HouseholdFounded{} = e),
    do: %{h | id: e.id, witnesses: MapSet.put(h.witnesses, e.account_id)}

  def apply(%__MODULE__{} = h, %Events.HouseholdWitnessJoined{} = e),
    do: %{h | witnesses: MapSet.put(h.witnesses, e.account_id)}

  def apply(%__MODULE__{} = h, %Events.HouseholdResidentJoined{} = e),
    do: %{h | residents: MapSet.put(h.residents, e.resident_id)}

  def apply(%__MODULE__{} = h, %Events.HouseholdResidentLeft{} = e),
    do: %{h | residents: MapSet.delete(h.residents, e.resident_id)}

  def apply(%__MODULE__{} = h, %Events.HouseholdTermsGranted{} = e),
    do: %{h | terms: {e.plan, e.price_nanos, e.terms_until}}

  defp terms_ok?(c) do
    is_binary(c.plan) and String.trim(c.plan) != "" and String.length(c.plan) <= @plan_limit and
      is_integer(c.price_nanos) and c.price_nanos >= 0 and match?(%DateTime{}, c.terms_until) and
      is_binary(c.source) and is_binary(c.note) and String.trim(c.note) != ""
  end
end
