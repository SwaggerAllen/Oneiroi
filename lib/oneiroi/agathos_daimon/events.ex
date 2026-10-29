defmodule Oneiroi.AgathosDaimon.Events do
  @moduledoc "The resident stream's events, version 1 (spec §3.1, §6.10)."

  defmodule ResidentCreated do
    use Oneiroi.Event, version: 1, fields: [:id, :name, :slug, :steward_account_id]
  end

  defmodule IdMinted do
    # The per-resident sequence (spec §2.2): `number` is read off the
    # aggregate's own counter for `kind`, so replay reproduces it.
    use Oneiroi.Event, version: 1, fields: [:id, :kind, :number]
  end

  defmodule ResidentPaused do
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule ResidentWoken do
    use Oneiroi.Event, version: 1, fields: [:id, :reason]
  end

  defmodule CustodyTransferred do
    # `from` and `to` are `{:account, id}` or `:community`, written as
    # `"account:<id>"` and `"community"` on the wire (`Oneiroi.AgathosDaimon.Custody`).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :from, :to]
  end

  defmodule ExportWallSet do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :wall]
  end

  defmodule Imported do
    use Oneiroi.Event, version: 1, fields: [:id, :source, :attestation, :root, :sequence]
  end

  # The export's own bookkeeping: in the log, never in the export
  # (`Oneiroi.Event`'s `export:`).
  defmodule ExportWritten do
    use Oneiroi.Event, version: 1, fields: [:id, :through, :files], export: false
  end

  defmodule BackupCommitted do
    use Oneiroi.Event, version: 1, fields: [:id, :sequence, :root, :commit], export: false
  end

  defmodule RootMismatchDetected do
    use Oneiroi.Event, version: 1, fields: [:id, :expected_root, :actual_root, :commit]
  end

  defmodule SeedFileWritten do
    # A seed file given before first contact (spec §6.2, F2): the file's
    # name, its whole content, and its origin: `authored`, `drafted` (with
    # the model and the prompt the draft came from) or `uploaded`. The
    # resident reads its own becoming from these.
    use Oneiroi.Event, version: 1, fields: [:id, :file, :content, :origin, :model, :prompt]
  end

  defmodule FirstContact do
    # The first captured turn in a session that is not a regression
    # session (spec §6.2): from here the files are proposed, not given,
    # and the formation clock runs.
    use Oneiroi.Event, version: 1, fields: [:id, :session_key, :turn_ref]
  end

  defmodule SoulEditProposed do
    # After first contact a steward's edit travels as a proposal; the
    # note is what the resident reads first.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref, :file, :content]
  end

  defmodule SoulEditAccepted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule SoulEditDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule SoulEditApplied do
    # The file as written after first contact: by the resident accepting
    # a proposal (`ref` set) or editing on its own (`ref` nil). One
    # commit each; rare, visible, reversible.
    use Oneiroi.Event, version: 1, fields: [:id, :ref, :file, :content]
  end

  defmodule RecordsRemoteSet do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :url, :token_ciphertext],
      redact: [:token_ciphertext]
  end
end
