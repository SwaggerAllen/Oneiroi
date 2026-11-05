defmodule Oneiroi.Gaia.HouseholdRouter do
  @moduledoc "The household aggregate's router (gaia#17): `household-<id>`, the billing owner and its memberships."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Gaia.Household",
    prefix: "household-",
    commands: "Oneiroi.Gaia.Commands",
    dispatching:
      ~w(FoundHousehold JoinHouseholdWitness JoinHouseholdResident LeaveHouseholdResident GrantHouseholdTerms)
end
