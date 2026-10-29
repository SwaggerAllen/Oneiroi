defmodule Oneiroi.HuginnMuninn.Router do
  @moduledoc "The audits router: `audits-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.HuginnMuninn.Audits",
    prefix: "audits-",
    commands: "Oneiroi.HuginnMuninn.Commands",
    dispatching:
      ~w(DefineCounter IncrementCounter RetireCounter DefineUserAudit RetireUserAudit RecordRun)
end
