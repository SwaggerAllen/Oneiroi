defmodule Oneiroi.AgathosDaimon.Router do
  @moduledoc "The resident aggregate's router."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.AgathosDaimon.Resident",
    prefix: "resident-",
    commands: "Oneiroi.AgathosDaimon.Commands",
    dispatching:
      ~w(CreateResident MintId PauseResident WakeResident TransferCustody SetExportWall ImportResident RecordExport RecordBackup RecordMismatch SetRecordsRemote WriteFile RecordFirstContact ProposeSoulEdit AcceptSoulEdit DeclineSoulEdit PinModel RecordModelTold RegisterAdapter RevokeAdapter SetTimezone)
end
