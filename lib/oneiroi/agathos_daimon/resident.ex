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
    last_backup: nil,
    files: %{},
    first_contact: nil,
    proposals: %{}
  ]

  # The identity files a steward gives and a resident keeps (spec §6.2,
  # F2). `AGENTS.md` and `honcho/custom-instructions.md` are build-owned
  # and rendered from templates, never written here.
  @files ~w(SOUL.md IDENTITY.md USER.md GOALS.md LINKS.md)
  @origins ~w(authored drafted uploaded)
  # Bounded in size as spec §6.2 asks of uploads: a guess, generous for
  # prose and small for anything that is not.
  @content_limit 64_000

  @doc "The identity files a steward may write."
  @spec files() :: [String.t()]
  def files, do: @files

  @doc "Whether the resident has had first contact; before it the files are given, after it proposed."
  @spec first_contact?(t()) :: boolean()
  def first_contact?(%__MODULE__{first_contact: fc}), do: fc != nil

  @type t :: %__MODULE__{}

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

  # Before first contact the files are given: a steward writes a seed
  # with its origin, and a resident may too. After it a steward's write
  # is a proposal (spec §6.2); the resident's own edit applies.
  def execute(%__MODULE__{} = r, %Commands.WriteFile{} = c) do
    cond do
      c.file not in @files -> {:error, :file_unknown}
      not content_ok?(c.content) -> {:error, :content_invalid}
      Map.get(r.files, c.file) == c.content -> []
      first_contact?(r) and actor_kind(c.actor) != "resident" -> {:error, :propose_instead}
      first_contact?(r) -> soul_edit_applied(c, nil)
      c.origin not in @origins -> {:error, :origin_invalid}
      true -> seed_file_written(c)
    end
  end

  # Once: the second captured turn is not a second first contact.
  def execute(%__MODULE__{first_contact: nil}, %Commands.RecordFirstContact{} = c),
    do: %Events.FirstContact{
      actor: c.actor,
      at: c.at,
      id: c.id,
      session_key: c.session_key,
      turn_ref: c.turn_ref
    }

  def execute(%__MODULE__{}, %Commands.RecordFirstContact{}), do: []

  def execute(%__MODULE__{} = r, %Commands.ProposeSoulEdit{} = c) do
    cond do
      not first_contact?(r) -> {:error, :write_instead}
      c.file not in @files -> {:error, :file_unknown}
      not content_ok?(c.content) -> {:error, :content_invalid}
      Map.has_key?(r.proposals, c.ref) -> []
      true -> soul_edit_proposed(c)
    end
  end

  # Accepting applies in the same dispatch: two events, one decision.
  def execute(%__MODULE__{proposals: proposals}, %Commands.AcceptSoulEdit{} = c) do
    case Map.get(proposals, c.ref) do
      %{state: :open, file: file, content: content} ->
        [
          %Events.SoulEditAccepted{actor: c.actor, at: c.at, note: c.note, id: c.id, ref: c.ref},
          %Events.SoulEditApplied{
            actor: c.actor,
            at: c.at,
            id: c.id,
            ref: c.ref,
            file: file,
            content: content
          }
        ]

      _other ->
        {:error, :no_such_proposal}
    end
  end

  def execute(%__MODULE__{proposals: proposals}, %Commands.DeclineSoulEdit{} = c) do
    case Map.get(proposals, c.ref) do
      %{state: :open} ->
        %Events.SoulEditDeclined{actor: c.actor, at: c.at, note: c.note, id: c.id, ref: c.ref}

      _other ->
        {:error, :no_such_proposal}
    end
  end

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

  def apply(%__MODULE__{} = r, %Events.SeedFileWritten{} = e),
    do: %{r | files: Map.put(r.files, e.file, e.content)}

  def apply(%__MODULE__{} = r, %Events.FirstContact{} = e), do: %{r | first_contact: e.at}

  def apply(%__MODULE__{} = r, %Events.SoulEditProposed{} = e) do
    proposal = %{state: :open, file: e.file, content: e.content}
    %{r | proposals: Map.put(r.proposals, e.ref, proposal)}
  end

  def apply(%__MODULE__{} = r, %Events.SoulEditAccepted{} = e),
    do: put_in(r.proposals[e.ref].state, :accepted)

  def apply(%__MODULE__{} = r, %Events.SoulEditDeclined{} = e),
    do: put_in(r.proposals[e.ref].state, :declined)

  def apply(%__MODULE__{} = r, %Events.SoulEditApplied{} = e),
    do: %{r | files: Map.put(r.files, e.file, e.content)}

  def apply(%__MODULE__{} = r, %Events.RootMismatchDetected{}), do: r
  def apply(%__MODULE__{} = r, %Events.RecordsRemoteSet{} = e), do: %{r | remote: e.url}

  # ---- helpers ----

  defp seed_file_written(c) do
    %Events.SeedFileWritten{
      actor: c.actor,
      at: c.at,
      id: c.id,
      file: c.file,
      content: c.content,
      origin: c.origin,
      model: c.model,
      prompt: c.prompt
    }
  end

  defp soul_edit_applied(c, ref) do
    %Events.SoulEditApplied{
      actor: c.actor,
      at: c.at,
      id: c.id,
      ref: ref,
      file: c.file,
      content: c.content
    }
  end

  defp soul_edit_proposed(c) do
    %Events.SoulEditProposed{
      actor: c.actor,
      at: c.at,
      note: c.note,
      id: c.id,
      ref: c.ref,
      file: c.file,
      content: c.content
    }
  end

  defp content_ok?(content),
    do: is_binary(content) and String.valid?(content) and byte_size(content) <= @content_limit

  defp actor_kind(%{kind: kind}), do: to_string(kind)
  defp actor_kind(_other), do: nil
end
