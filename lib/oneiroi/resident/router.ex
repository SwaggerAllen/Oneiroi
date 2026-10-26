defmodule Oneiroi.Resident.Router do
  @moduledoc "The resident aggregate's router."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Resident.Resident",
    prefix: "resident-",
    commands: "Oneiroi.Resident.Commands",
    dispatching:
      ~w(CreateResident MintId PauseResident WakeResident TransferCustody SetExportWall ImportResident RecordExport RecordBackup RecordMismatch SetRecordsRemote)
end
