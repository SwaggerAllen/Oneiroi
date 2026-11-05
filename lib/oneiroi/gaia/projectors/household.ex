defmodule Oneiroi.Gaia.Projectors.Household do
  @moduledoc "Folds the household streams (gaia#17) into the household row and its two kinds of membership."
  use Oneiroi.Projection, name: "gaia_household"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Store.{Household, HouseholdResident, HouseholdWitness}

  fold(%Events.HouseholdFounded{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(:household, %Household{id: e.id, founded_by: e.account_id, founded_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:id]
    )
    |> Multi.insert(
      :witness,
      %HouseholdWitness{household_id: e.id, account_id: e.account_id, joined_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:household_id, :account_id]
    )
  end)

  fold(%Events.HouseholdWitnessJoined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :witness,
      %HouseholdWitness{household_id: e.id, account_id: e.account_id, joined_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:household_id, :account_id]
    )
  end)

  fold(%Events.HouseholdResidentJoined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :resident,
      %HouseholdResident{household_id: e.id, resident_id: e.resident_id, joined_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:household_id, :resident_id]
    )
  end)

  fold(%Events.HouseholdResidentLeft{} = e, _metadata, fn multi ->
    Multi.delete_all(
      multi,
      :resident,
      from(r in HouseholdResident,
        where: r.household_id == ^e.id and r.resident_id == ^e.resident_id
      )
    )
  end)

  fold(%Events.HouseholdTermsGranted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :terms,
      from(h in Household, where: h.id == ^e.id),
      set: [
        plan: e.plan,
        price_nanos: e.price_nanos,
        terms_until: e.terms_until,
        terms_source: e.source,
        terms_note: e.note
      ]
    )
  end)
end
