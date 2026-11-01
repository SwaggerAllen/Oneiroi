defmodule Oneiroi.AgathosDaimon.Router do
  @moduledoc "The resident aggregate's router."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.AgathosDaimon.Resident",
    prefix: "resident-",
    commands: "Oneiroi.AgathosDaimon.Commands",
    dispatching:
      ~w(CreateResident MintId PauseResident WakeResident TransferCustody SetExportWall ImportResident RecordExport RecordBackup RecordMismatch SetRecordsRemote WriteFile RecordFirstContact ProposeSoulEdit AcceptSoulEdit DeclineSoulEdit PinModel RecordModelTold RegisterAdapter RevokeAdapter SetTimezone LapseResident ResumeResident ProposeContract AgreeContract DeclineContract ProposeCustodyTransfer AcceptCustodyTransfer DeclineCustodyTransfer WithdrawCustodyTransfer CompleteImport RecordImportTold RecordContinuationAsk RenewContract WriteSelfLetter DeliverSelfLetters ReadSelfLetters MarkSelfLettersExported)

  alias Oneiroi.AgathosDaimon.Error

  @doc """
  Dispatches `command` and returns its events, or an error that names
  its site. The aggregate's refusals arrive sited already, at the clause
  that decided them (`Oneiroi.AgathosDaimon.Resident`); what is wrapped
  here is the command bus's own failure (a command the actor middleware
  refused, a timeout), once, with the command it was carrying, since
  every caller of this router shares the line.
  """
  @spec dispatch_sited(struct()) :: {:ok, [struct()]} | {:error, Error.t()}
  def dispatch_sited(command) do
    case __MODULE__.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(:agathos_daimon_dispatch_failed, :agathos_daimon_router_dispatch, reason,
           command: command.__struct__
         )}
    end
  end
end
