defmodule Oneiroi.Nisaba.Router do
  @moduledoc "The ledger aggregate's router; strong consistency and the actor middleware come with `Oneiroi.Router`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Nisaba.Ledger",
    prefix: "ledger-",
    commands: "Oneiroi.Nisaba.Commands",
    dispatching: ~w(SetBudget RecordModelCall)
end
