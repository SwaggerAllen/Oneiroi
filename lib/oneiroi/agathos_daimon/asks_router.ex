defmodule Oneiroi.AgathosDaimon.AsksRouter do
  @moduledoc "The asks aggregate's router (agathos-daimon#35): `asks-<resident_id>`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.AgathosDaimon.Asks",
    prefix: "asks-",
    commands: "Oneiroi.AgathosDaimon.Commands",
    dispatching: ~w(MakeAsk AnswerAsk)
end
