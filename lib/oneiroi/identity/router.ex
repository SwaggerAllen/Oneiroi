defmodule Oneiroi.Identity.Router do
  @moduledoc "The account aggregate's router; strong consistency and the actor middleware come with `Oneiroi.Router`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Identity.Account",
    prefix: "account-",
    commands: "Oneiroi.Identity.Commands",
    dispatching:
      ~w(CreateAccount EnrollSecondFactor OpenSession CloseSession IssueToken RevokeToken
         StartStewardship EndStewardship)
end
