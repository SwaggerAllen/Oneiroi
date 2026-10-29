defmodule Oneiroi.Proteus.Router do
  @moduledoc "The bridge router: `honcho-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Proteus.Bridge",
    prefix: "honcho-",
    commands: "Oneiroi.Proteus.Commands",
    dispatching: ~w(Provision AddPeer RecordCard RecordCardAudit RecordSync RecordKey)
end
