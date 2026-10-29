defmodule Oneiroi.AgathosDaimon.Commands do
  @moduledoc "The resident aggregate's commands (spec §3.1)."

  defmodule CreateResident do
    use Oneiroi.Command, fields: [:id, :name, :slug, :steward_account_id]
  end

  defmodule MintId do
    use Oneiroi.Command, fields: [:id, :kind]
  end

  defmodule PauseResident do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule WakeResident do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule TransferCustody do
    # A decision: the note is what the resident reads first.
    use Oneiroi.Command, decision: true, fields: [:id, :to]
  end

  defmodule SetExportWall do
    use Oneiroi.Command, decision: true, fields: [:id, :wall]
  end

  defmodule ImportResident do
    use Oneiroi.Command, fields: [:id, :source, :attestation, :root, :sequence]
  end

  defmodule RecordExport do
    use Oneiroi.Command, fields: [:id, :through, :files]
  end

  defmodule RecordBackup do
    use Oneiroi.Command, fields: [:id, :sequence, :root, :commit]
  end

  defmodule RecordMismatch do
    use Oneiroi.Command, fields: [:id, :expected_root, :actual_root, :commit]
  end

  defmodule WriteFile do
    # Before first contact: a seed, with its origin. After: the resident's
    # own edit, and a steward's is refused in favour of a proposal.
    use Oneiroi.Command, fields: [:id, :file, :content, :origin, :model, :prompt]
  end

  defmodule RecordFirstContact do
    use Oneiroi.Command, fields: [:id, :session_key, :turn_ref]
  end

  defmodule ProposeSoulEdit do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :file, :content]
  end

  defmodule AcceptSoulEdit do
    use Oneiroi.Command, decision: true, fields: [:id, :ref]
  end

  defmodule DeclineSoulEdit do
    use Oneiroi.Command, decision: true, fields: [:id, :ref]
  end

  defmodule SetRecordsRemote do
    use Oneiroi.Command, fields: [:id, :url, :token_ciphertext]
  end
end
