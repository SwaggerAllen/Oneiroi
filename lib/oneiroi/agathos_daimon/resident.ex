defmodule Oneiroi.AgathosDaimon.Resident do
  @moduledoc """
  The resident aggregate on `resident-<id>`. Pure (conventions §6): no
  clock, no randomness, no ids but the ones its own counters mint.

  The counters are the per-resident id sequences (spec §2.2): one per
  kind, held in state, so an event that mints a citeable id carries it
  and a replay reproduces every number. Two residents cannot interleave
  because each holds its own.
  """

  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Custody
  alias Oneiroi.AgathosDaimon.Events

  defstruct [
    :id,
    :name,
    :slug,
    :steward_account_id,
    :custody,
    :export_wall,
    :import,
    :remote,
    state: :absent,
    sequences: %{},
    exported_through: 0,
    last_backup: nil
  ]

  # ---- execute ----

  def execute(%__MODULE__{state: :absent}, %Commands.CreateResident{} = c) do
    %Events.ResidentCreated{
      actor: c.actor,
      at: c.at,
      id: c.id,
      name: c.name,
      slug: c.slug,
      steward_account_id: c.steward_account_id
    }
  end

  def execute(%__MODULE__{}, %Commands.CreateResident{}), do: {:error, :resident_exists}

  # An import writes the source's own events first; this command lands
  # after them on a stream that already holds a resident.
  def execute(%__MODULE__{state: s}, %Commands.ImportResident{} = c) when s != :absent do
    %Events.Imported{
      actor: c.actor,
      at: c.at,
      id: c.id,
      source: c.source,
      attestation: c.attestation,
      root: c.root,
      sequence: c.sequence
    }
  end

  def execute(%__MODULE__{state: :absent}, _command), do: {:error, :no_such_resident}

  def execute(%__MODULE__{sequences: sequences}, %Commands.MintId{} = c) do
    %Events.IdMinted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      kind: c.kind,
      number: Map.get(sequences, c.kind, 0) + 1
    }
  end

  def execute(%__MODULE__{state: :active}, %Commands.PauseResident{} = c),
    do: %Events.ResidentPaused{actor: c.actor, at: c.at, id: c.id, reason: c.reason}

  def execute(%__MODULE__{}, %Commands.PauseResident{}), do: {:error, :not_active}

  def execute(%__MODULE__{state: :paused}, %Commands.WakeResident{} = c),
    do: %Events.ResidentWoken{actor: c.actor, at: c.at, id: c.id, reason: c.reason}

  def execute(%__MODULE__{}, %Commands.WakeResident{}), do: {:error, :not_paused}

  def execute(%__MODULE__{custody: from}, %Commands.TransferCustody{} = c) do
    %Events.CustodyTransferred{
      actor: c.actor,
      at: c.at,
      note: c.note,
      id: c.id,
      from: Custody.to_wire(from),
      to: Custody.to_wire(c.to)
    }
  end

  def execute(%__MODULE__{}, %Commands.SetExportWall{wall: wall} = c)
      when wall in [:locked, :revealed] do
    %Events.ExportWallSet{
      actor: c.actor,
      at: c.at,
      note: c.note,
      id: c.id,
      wall: Atom.to_string(wall)
    }
  end

  def execute(%__MODULE__{}, %Commands.SetExportWall{}), do: {:error, :wall_is_locked_or_revealed}

  def execute(%__MODULE__{}, %Commands.RecordExport{} = c),
    do: %Events.ExportWritten{
      actor: c.actor,
      at: c.at,
      id: c.id,
      through: c.through,
      files: c.files
    }

  def execute(%__MODULE__{}, %Commands.RecordBackup{} = c),
    do: %Events.BackupCommitted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      sequence: c.sequence,
      root: c.root,
      commit: c.commit
    }

  def execute(%__MODULE__{}, %Commands.RecordMismatch{} = c),
    do: %Events.RootMismatchDetected{
      actor: c.actor,
      at: c.at,
      id: c.id,
      expected_root: c.expected_root,
      actual_root: c.actual_root,
      commit: c.commit
    }

  def execute(%__MODULE__{}, %Commands.SetRecordsRemote{} = c),
    do: %Events.RecordsRemoteSet{
      actor: c.actor,
      at: c.at,
      id: c.id,
      url: c.url,
      token_ciphertext: c.token_ciphertext
    }

  # ---- apply ----

  def apply(%__MODULE__{} = r, %Events.ResidentCreated{} = e) do
    %{
      r
      | id: e.id,
        name: e.name,
        slug: e.slug,
        steward_account_id: e.steward_account_id,
        custody: {:account, e.steward_account_id},
        state: :active
    }
  end

  def apply(%__MODULE__{} = r, %Events.IdMinted{} = e),
    do: %{r | sequences: Map.put(r.sequences, e.kind, e.number)}

  def apply(%__MODULE__{} = r, %Events.ResidentPaused{}), do: %{r | state: :paused}
  def apply(%__MODULE__{} = r, %Events.ResidentWoken{}), do: %{r | state: :active}

  def apply(%__MODULE__{} = r, %Events.CustodyTransferred{} = e) do
    case Custody.from_wire(e.to) do
      {:account, id} -> %{r | custody: {:account, id}, steward_account_id: id}
      :community -> %{r | custody: :community, steward_account_id: nil, state: :community}
    end
  end

  def apply(%__MODULE__{} = r, %Events.ExportWallSet{} = e),
    do: %{r | export_wall: String.to_existing_atom(e.wall)}

  def apply(%__MODULE__{} = r, %Events.Imported{} = e),
    do: %{r | import: %{source: e.source, attestation: e.attestation, root: e.root}}

  def apply(%__MODULE__{} = r, %Events.ExportWritten{} = e),
    do: %{r | exported_through: e.through}

  def apply(%__MODULE__{} = r, %Events.BackupCommitted{} = e),
    do: %{r | last_backup: %{sequence: e.sequence, root: e.root, commit: e.commit}}

  def apply(%__MODULE__{} = r, %Events.RootMismatchDetected{}), do: r
  def apply(%__MODULE__{} = r, %Events.RecordsRemoteSet{} = e), do: %{r | remote: e.url}
end
