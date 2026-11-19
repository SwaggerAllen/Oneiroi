defmodule Oneiroi.Gaia.RoundsRouter do
  @moduledoc "A household's round-robin threads (gaia#53): `rounds-<household id>`, every thread's rounds and tokens."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Gaia.Rounds",
    prefix: "rounds-",
    commands: "Oneiroi.Gaia.Commands",
    dispatching: ~w(StartRounds SpendTurn EndRoundTurn OptOutOfRounds OptIntoRounds)
end
