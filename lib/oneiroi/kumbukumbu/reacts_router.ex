defmodule Oneiroi.Kumbukumbu.ReactsRouter do
  @moduledoc "The reacts ledger's router: `reacts-<resident_id>` (kumbukumbu#56)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Kumbukumbu.ReactsLedger",
    prefix: "reacts-",
    commands: "Oneiroi.Kumbukumbu.Commands",
    dispatching: ~w(React TellReacts)
end
