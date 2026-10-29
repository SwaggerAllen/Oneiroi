defmodule Oneiroi.Glitnir.Router do
  @moduledoc "The governance router: `governance-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Glitnir.Reports",
    prefix: "governance-",
    commands: "Oneiroi.Glitnir.Commands",
    dispatching: ~w(FileReport RecordStep ResolveReport)
end
