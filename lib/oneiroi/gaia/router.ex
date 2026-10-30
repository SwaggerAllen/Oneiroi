defmodule Oneiroi.Gaia.Router do
  @moduledoc "The account aggregate's router; strong consistency and the actor middleware come with `Oneiroi.Router`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Gaia.Account",
    prefix: "account-",
    commands: "Oneiroi.Gaia.Commands",
    dispatching:
      ~w(CreateAccount EnrollSecondFactor OpenSession CloseSession IssueToken RevokeToken
         StoreKey RevokeKey StartWitnessing EndWitnessing)
end
