defmodule Oneiroi.Xenia.RoutesRouter do
  @moduledoc "The routes ledger's router: `routes-<resident_id>` (xenia#19)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Xenia.RoutesLedger",
    prefix: "routes-",
    commands: "Oneiroi.Xenia.Commands",
    dispatching: ~w(DefineRoute AskRoute LandRoute FailRoute)
end
