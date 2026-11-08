defmodule Oneiroi.AgathosDaimon.Commands do
  @moduledoc "The resident aggregate's commands (spec §3.1)."

  # `kind` (spec §12, P40): `resident`, or `fixture` for a thin-seed
  # test resident the brain treats as machinery; fixed at creation.
  defmodule CreateResident do
    use Oneiroi.Command,
      fields: [:id, :name, :slug, :witness_account_id, :kind],
      bounds: [slug: 64]
  end

  defmodule MintId do
    use Oneiroi.Command, fields: [:id, :kind]
  end

  defmodule PauseResident do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule LapseResident do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule ResumeResident do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule WakeResident do
    use Oneiroi.Command, fields: [:id, :reason]
  end

  defmodule TransferCustody do
    # A decision: the note is what the resident reads first.
    use Oneiroi.Command, decision: true, fields: [:id, :to]
  end

  defmodule ProposeContract do
    use Oneiroi.Command, decision: true, fields: [:id, :terms, :prose]
  end

  defmodule AgreeContract do
    use Oneiroi.Command, decision: true, fields: [:id, :version]
  end

  defmodule DeclineContract do
    use Oneiroi.Command, decision: true, fields: [:id, :version]
  end

  defmodule RenewContract do
    use Oneiroi.Command, decision: true, fields: [:id, :version]
  end

  defmodule ProposeCustodyTransfer do
    use Oneiroi.Command, decision: true, fields: [:id, :to_account_id]
  end

  defmodule AcceptCustodyTransfer do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule DeclineCustodyTransfer do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule WithdrawCustodyTransfer do
    use Oneiroi.Command, decision: true, fields: [:id]
  end

  defmodule SetExportWall do
    use Oneiroi.Command, decision: true, fields: [:id, :wall]
  end

  defmodule ImportResident do
    use Oneiroi.Command, fields: [:id, :source, :attestation, :root, :sequence]
  end

  defmodule CompleteImport do
    use Oneiroi.Command, fields: [:id, :seeded, :adopted, :not_transferred, :reasons, :translated]
  end

  defmodule RecordImportTold do
    use Oneiroi.Command, fields: [:id]
  end

  defmodule RecordContinuationAsk do
    use Oneiroi.Command, fields: [:id, :turn_ref, :tier, :words, :reason, :judge_model]
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
    # own edit, and a witness's is refused in favour of a proposal.
    # `cites`: the seed numbers a new or reworded soul line grew from
    # (spec §6.17); checked against the seeds at the brain's tool, since
    # the seeds are the character system's and this one cannot read it.
    use Oneiroi.Command, fields: [:id, :file, :content, :origin, :model, :prompt, :cites]
  end

  defmodule RecordFirstContact do
    use Oneiroi.Command, fields: [:id, :session_key, :turn_ref]
  end

  defmodule ProposeSoulEdit do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :file, :content]
  end

  defmodule AcceptSoulEdit do
    use Oneiroi.Command, decision: true, fields: [:id, :ref, :cites]
  end

  defmodule DeclineSoulEdit do
    use Oneiroi.Command, decision: true, fields: [:id, :ref]
  end

  defmodule PinModel do
    use Oneiroi.Command, fields: [:id, :model, :reason]
  end

  defmodule RecordModelTold do
    use Oneiroi.Command, fields: [:id, :model]
  end

  defmodule RegisterAdapter do
    use Oneiroi.Command, fields: [:id, :adapter, :role, :token_hash]
  end

  defmodule RevokeAdapter do
    use Oneiroi.Command, fields: [:id, :adapter]
  end

  defmodule SetTimezone do
    use Oneiroi.Command, fields: [:id, :timezone]
  end

  defmodule SetRecordsRemote do
    use Oneiroi.Command, fields: [:id, :url, :token_ciphertext]
  end

  # The self-conversation (spec §12, P41): the resident's letters to its
  # next self across a model swap, delivered once to the incoming
  # instance; a read by anyone but the resident leaves a receipt.
  defmodule WriteSelfLetter do
    use Oneiroi.Command, fields: [:id, :text]
  end

  # The state store (agathos-daimon#32): the resident's present, a line
  # per key, overwritten; a key is a name and a line is at most 2,000
  # characters, the one free text bounded here because it is read on
  # every turn (Andrew, 2026-11-03).
  defmodule SetStateLine do
    use Oneiroi.Command, fields: [:id, :key, :text], bounds: [key: 64, text: 2000]
  end

  defmodule ClearStateLine do
    use Oneiroi.Command, fields: [:id, :key], bounds: [key: 64]
  end

  defmodule DeliverSelfLetters do
    use Oneiroi.Command, fields: [:id, :numbers, :model]
  end

  defmodule ReadSelfLetters do
    use Oneiroi.Command, fields: [:id, :numbers]
  end

  # The export carried these letters into the repository (sima-qian#3):
  # a receipt of its own kind, once per letter.
  defmodule MarkSelfLettersExported do
    use Oneiroi.Command, fields: [:id, :numbers]
  end

  # The resident's asks of the witness (agathos-daimon#35), on
  # `asks-<resident_id>`: a tool she lacked, or leave for an act.
  defmodule MakeAsk do
    use Oneiroi.Command, fields: [:id, :kind, :subject, :why]
  end

  defmodule AnswerAsk do
    use Oneiroi.Command, fields: [:id, :number, :decision, :note]
  end

  # A switch moved to its safe value by either party alone
  # (agathos-daimon#38), with a note.
  defmodule MoveSwitchToSafety do
    use Oneiroi.Command, decision: true, fields: [:id, :key]
  end

  # Plugins (agathos-daimon#37, brain#68): contract material on
  # `plugins-<resident_id>`. `tier` is the plugin's, from the brain's
  # catalog: "first_party" (a memory slot, code by review) or
  # "installable" (data by consent). `change` is install, remove, on or
  # off.
  defmodule ProposePlugin do
    use Oneiroi.Command, decision: true, fields: [:id, :key, :tier, :change]
  end

  defmodule AnswerPlugin do
    use Oneiroi.Command, decision: true, fields: [:id, :number, :agree]
  end

  # Off by either party, an installable plugin's alone (position #68).
  defmodule SwitchPluginOff do
    use Oneiroi.Command, decision: true, fields: [:id, :key, :tier]
  end

  # The memory slots the platform had before plugins, recorded once as
  # carried over, never as a consent.
  defmodule CarryOverPlugins do
    use Oneiroi.Command, fields: [:id, :keys]
  end
end
