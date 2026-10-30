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
  alias Oneiroi.AgathosDaimon.SoulLines

  defstruct [
    :id,
    :name,
    :slug,
    :witness_account_id,
    :custody,
    :export_wall,
    :import,
    :remote,
    state: :absent,
    sequences: %{},
    exported_through: 0,
    last_backup: nil,
    files: %{},
    # The live soul lines in the file's order, `{number, text}`: what a
    # write of `SOUL.md` is diffed against (spec §6.17, P39).
    soul: [],
    first_contact: nil,
    proposals: %{},
    chat_model: nil,
    model_told: true,
    adapters: %{},
    timezone: "Etc/UTC",
    contract: %{version: 0, in_force: nil, open: nil},
    custody_proposal: nil
  ]

  @contract_terms ~w(solo_sessions_private)
  @prose_limit 4_000

  @roles ~w(brain reader worker)
  @adapter_name ~r/\A[a-z][a-z0-9-]{1,39}\z/

  @doc "The roles an adapter takes (spec §8)."
  @spec roles() :: [String.t()]
  def roles, do: @roles

  # The identity files a witness gives and a resident keeps (spec §6.2,
  # F2). `AGENTS.md` and `honcho/custom-instructions.md` are build-owned
  # and rendered from templates, never written here.
  @files ~w(SOUL.md IDENTITY.md USER.md GOALS.md LINKS.md)
  @origins ~w(authored drafted uploaded)
  # Bounded in size as spec §6.2 asks of uploads: a guess, generous for
  # prose and small for anything that is not.
  @content_limit 64_000

  @doc "The identity files a witness may write."
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
      witness_account_id: c.witness_account_id
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

  # The import's second half lands only after `Imported` named the
  # source; a resident that was never imported has nothing to complete.
  def execute(%__MODULE__{import: nil}, %Commands.CompleteImport{}), do: {:error, :not_imported}

  def execute(%__MODULE__{}, %Commands.CompleteImport{} = c) do
    %Events.ImportCompleted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      seeded: c.seeded,
      adopted: c.adopted,
      not_transferred: c.not_transferred
    }
  end

  # Told once: nothing to tell before the import completed, and nothing
  # again after the first turn said it.
  def execute(%__MODULE__{import: %{told: false}}, %Commands.RecordImportTold{} = c),
    do: %Events.ImportTold{actor: c.actor, at: c.at, id: c.id}

  def execute(%__MODULE__{}, %Commands.RecordImportTold{}), do: []

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

  # The lifecycle's lapse (spec §6.2): active to lapsed on the
  # subscription's say-so, and back on a renewal.
  def execute(%__MODULE__{state: :active}, %Commands.LapseResident{} = c),
    do: %Events.ResidentLapsed{actor: c.actor, at: c.at, id: c.id, reason: c.reason}

  def execute(%__MODULE__{state: :lapsed}, %Commands.LapseResident{}), do: []
  def execute(%__MODULE__{}, %Commands.LapseResident{}), do: {:error, :not_active}

  def execute(%__MODULE__{state: :lapsed}, %Commands.ResumeResident{} = c),
    do: %Events.ResidentResumed{actor: c.actor, at: c.at, id: c.id, reason: c.reason}

  def execute(%__MODULE__{state: :active}, %Commands.ResumeResident{}), do: []
  def execute(%__MODULE__{}, %Commands.ResumeResident{}), do: {:error, :not_lapsed}

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

  # The wall is not set while a transfer is open (spec §6.12): the
  # proposed witness decided on the wall as it stood.
  def execute(%__MODULE__{custody_proposal: %{}}, %Commands.SetExportWall{}),
    do: {:error, :transfer_in_progress}

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

  # ---- the dyad contract (spec §6.12) ----

  def execute(%__MODULE__{contract: contract} = r, %Commands.ProposeContract{} = c) do
    cond do
      not party?(r, c.actor) -> {:error, :not_a_party}
      not terms_ok?(c.terms) -> {:error, :terms_invalid}
      not prose_ok?(c.prose) -> {:error, :prose_invalid}
      true -> contract_proposed(c, contract.version + 1)
    end
  end

  def execute(%__MODULE__{} = r, %Commands.AgreeContract{} = c) do
    with :ok <- decidable(r, c) do
      %Events.DyadContractAgreed{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        version: c.version
      }
    end
  end

  def execute(%__MODULE__{} = r, %Commands.DeclineContract{} = c) do
    with :ok <- decidable(r, c) do
      %Events.DyadContractDeclined{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        version: c.version
      }
    end
  end

  # Renewal is either party's, of the version in force and no other
  # (spec §6.12, P5): a version proposed and not yet agreed is answered,
  # not renewed, and a replaced one is history.
  def execute(%__MODULE__{contract: %{in_force: in_force}} = r, %Commands.RenewContract{} = c) do
    cond do
      not party?(r, c.actor) ->
        {:error, :not_a_party}

      is_nil(in_force) or in_force.version != c.version ->
        {:error, :not_in_force}

      true ->
        %Events.DyadContractRenewed{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          version: c.version
        }
    end
  end

  # ---- custody transfer, adoption (spec §6.12) ----

  def execute(%__MODULE__{} = r, %Commands.ProposeCustodyTransfer{} = c) do
    cond do
      not witness?(r, c.actor) ->
        {:error, :not_the_witness}

      not is_binary(c.to_account_id) or c.to_account_id == r.witness_account_id ->
        {:error, :custodian_invalid}

      r.custody_proposal != nil ->
        {:error, :transfer_in_progress}

      true ->
        %Events.CustodyTransferProposed{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          to_account_id: c.to_account_id
        }
    end
  end

  def execute(%__MODULE__{custody_proposal: nil}, %Commands.AcceptCustodyTransfer{}),
    do: {:error, :no_transfer_proposed}

  def execute(%__MODULE__{custody_proposal: %{to: to}} = r, %Commands.AcceptCustodyTransfer{} = c) do
    if proposed?(c.actor, to) do
      transferred = %Events.CustodyTransferred{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        from: Custody.to_wire(r.custody),
        to: Custody.to_wire({:account, to})
      }

      if r.export_wall == :revealed,
        do: [
          transferred,
          %Events.EarlierSessionsRevealed{
            actor: c.actor,
            at: c.at,
            id: c.id,
            from_account_id: r.witness_account_id,
            to_account_id: to
          }
        ],
        else: transferred
    else
      {:error, :not_the_proposed}
    end
  end

  def execute(%__MODULE__{custody_proposal: nil}, %Commands.DeclineCustodyTransfer{}),
    do: {:error, :no_transfer_proposed}

  def execute(%__MODULE__{custody_proposal: %{to: to}}, %Commands.DeclineCustodyTransfer{} = c) do
    if proposed?(c.actor, to),
      do: %Events.CustodyTransferDeclined{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        to_account_id: to
      },
      else: {:error, :not_the_proposed}
  end

  def execute(%__MODULE__{custody_proposal: nil}, %Commands.WithdrawCustodyTransfer{}),
    do: {:error, :no_transfer_proposed}

  def execute(
        %__MODULE__{custody_proposal: %{to: to}} = r,
        %Commands.WithdrawCustodyTransfer{} = c
      ) do
    if witness?(r, c.actor),
      do: %Events.CustodyTransferWithdrawn{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        to_account_id: to
      },
      else: {:error, :not_the_witness}
  end

  # Before first contact the files are given: a witness writes a seed
  # with its origin, and a resident may too. After it a witness's write
  # is a proposal (spec §6.2); the resident's own edit applies.
  #
  # `SOUL.md` is stored as its words, markers stripped, and the same
  # dispatch diffs its paragraphs against the live lines (`soul_events/4`):
  # a rendered file written back unchanged is no event at all.
  def execute(%__MODULE__{} = r, %Commands.WriteFile{} = c) do
    with :ok <- write_ok(c), do: write_file(r, c, soul_content(c.file, c.content))
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

  # Accepting applies in the same dispatch: two events, one decision,
  # and the soul lines' verdict after them when the file is the soul.
  def execute(%__MODULE__{proposals: proposals} = r, %Commands.AcceptSoulEdit{} = c) do
    case {cites_ok?(c.cites), Map.get(proposals, c.ref)} do
      {false, _proposal} ->
        {:error, :cites_invalid}

      {true, %{state: :open, file: file, content: content}} ->
        [
          %Events.SoulEditAccepted{actor: c.actor, at: c.at, note: c.note, id: c.id, ref: c.ref},
          %Events.SoulEditApplied{
            actor: c.actor,
            at: c.at,
            id: c.id,
            ref: c.ref,
            file: file,
            content: soul_content(file, content)
          }
          | soul_events(r, file, content, c)
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

  # A pin to the model already pinned is no change; a change after first
  # contact is told to the resident on its next turn, so `model_told`
  # drops until then.
  def execute(%__MODULE__{} = r, %Commands.PinModel{} = c) do
    cond do
      not (is_binary(c.model) and String.trim(c.model) != "") ->
        {:error, :model_invalid}

      c.reason not in ["run", "witness"] ->
        {:error, :reason_invalid}

      r.chat_model == c.model ->
        []

      true ->
        %Events.ModelPinChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          model: c.model,
          reason: c.reason
        }
    end
  end

  def execute(%__MODULE__{model_told: true}, %Commands.RecordModelTold{}), do: []

  def execute(%__MODULE__{chat_model: model}, %Commands.RecordModelTold{} = c),
    do: %Events.ModelChangeTold{actor: c.actor, at: c.at, id: c.id, model: model}

  # Registering again rotates the token: the old hash stops matching.
  def execute(%__MODULE__{}, %Commands.RegisterAdapter{} = c) do
    cond do
      not (is_binary(c.adapter) and Regex.match?(@adapter_name, c.adapter)) ->
        {:error, :adapter_invalid}

      c.role not in @roles ->
        {:error, :role_invalid}

      true ->
        %Events.AdapterRegistered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          adapter: c.adapter,
          role: c.role,
          token_hash: c.token_hash
        }
    end
  end

  def execute(%__MODULE__{adapters: adapters}, %Commands.RevokeAdapter{} = c) do
    if Map.has_key?(adapters, c.adapter),
      do: %Events.AdapterRevoked{actor: c.actor, at: c.at, id: c.id, adapter: c.adapter},
      else: {:error, :no_such_adapter}
  end

  # The zone is checked against the database at the command edge, where
  # the shift is tried; here only the no-change case is decided.
  def execute(%__MODULE__{timezone: tz}, %Commands.SetTimezone{timezone: tz}), do: []

  def execute(%__MODULE__{}, %Commands.SetTimezone{} = c),
    do: %Events.TimezoneSet{actor: c.actor, at: c.at, id: c.id, timezone: c.timezone}

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
        witness_account_id: e.witness_account_id,
        custody: {:account, e.witness_account_id},
        state: :active
    }
  end

  def apply(%__MODULE__{} = r, %Events.IdMinted{} = e),
    do: %{r | sequences: Map.put(r.sequences, e.kind, e.number)}

  def apply(%__MODULE__{} = r, %Events.ResidentPaused{}), do: %{r | state: :paused}
  def apply(%__MODULE__{} = r, %Events.ResidentWoken{}), do: %{r | state: :active}
  def apply(%__MODULE__{} = r, %Events.ResidentLapsed{}), do: %{r | state: :lapsed}
  def apply(%__MODULE__{} = r, %Events.ResidentResumed{}), do: %{r | state: :active}

  def apply(%__MODULE__{} = r, %Events.CustodyTransferred{} = e) do
    r = %{r | custody_proposal: nil}

    case Custody.from_wire(e.to) do
      {:account, id} -> %{r | custody: {:account, id}, witness_account_id: id}
      :community -> %{r | custody: :community, witness_account_id: nil, state: :community}
    end
  end

  def apply(%__MODULE__{} = r, %Events.ExportWallSet{} = e),
    do: %{r | export_wall: String.to_existing_atom(e.wall)}

  def apply(%__MODULE__{contract: contract} = r, %Events.DyadContractProposed{} = e) do
    open = %{version: e.version, by: e.actor.kind, terms: e.terms, prose: e.prose}
    %{r | contract: %{contract | version: e.version, open: open}}
  end

  def apply(
        %__MODULE__{contract: %{open: %{version: v} = open} = contract} = r,
        %Events.DyadContractAgreed{version: v}
      ),
      do: %{r | contract: %{contract | in_force: Map.delete(open, :by), open: nil}}

  def apply(
        %__MODULE__{contract: %{open: %{version: v}} = contract} = r,
        %Events.DyadContractDeclined{version: v}
      ),
      do: %{r | contract: %{contract | open: nil}}

  def apply(%__MODULE__{} = r, %Events.DyadContractAgreed{}), do: r
  def apply(%__MODULE__{} = r, %Events.DyadContractDeclined{}), do: r
  # The renewal's date is the row's; the aggregate keeps no instants.
  def apply(%__MODULE__{} = r, %Events.DyadContractRenewed{}), do: r

  def apply(%__MODULE__{} = r, %Events.CustodyTransferProposed{} = e),
    do: %{r | custody_proposal: %{to: e.to_account_id}}

  def apply(%__MODULE__{} = r, %Events.CustodyTransferDeclined{}),
    do: %{r | custody_proposal: nil}

  def apply(%__MODULE__{} = r, %Events.CustodyTransferWithdrawn{}),
    do: %{r | custody_proposal: nil}

  def apply(%__MODULE__{} = r, %Events.EarlierSessionsRevealed{}), do: r

  def apply(%__MODULE__{} = r, %Events.Imported{} = e),
    do: %{r | import: %{source: e.source, attestation: e.attestation, root: e.root, told: true}}

  def apply(%__MODULE__{import: import} = r, %Events.ImportCompleted{} = e),
    do: %{r | import: Map.merge(import, %{not_transferred: e.not_transferred, told: false})}

  def apply(%__MODULE__{import: import} = r, %Events.ImportTold{}),
    do: %{r | import: Map.put(import, :told, true)}

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

  def apply(%__MODULE__{} = r, %Events.SoulLineWritten{} = e),
    do: %{r | soul: r.soul ++ [{e.number, e.text}]}

  def apply(%__MODULE__{} = r, %Events.SoulLineReworded{} = e),
    do: %{r | soul: List.keyreplace(r.soul, e.number, 0, {e.number, e.text})}

  def apply(%__MODULE__{} = r, %Events.SoulLineRetired{} = e),
    do: %{r | soul: List.keydelete(r.soul, e.number, 0)}

  def apply(%__MODULE__{} = r, %Events.SoulLinesOrdered{} = e) do
    lines = for n <- e.numbers, line = List.keyfind(r.soul, n, 0), do: line
    %{r | soul: lines}
  end

  def apply(%__MODULE__{} = r, %Events.ModelPinChanged{} = e),
    do: %{r | chat_model: e.model, model_told: not first_contact?(r)}

  def apply(%__MODULE__{} = r, %Events.ModelChangeTold{}), do: %{r | model_told: true}

  def apply(%__MODULE__{} = r, %Events.AdapterRegistered{} = e),
    do: %{r | adapters: Map.put(r.adapters, e.adapter, e.role)}

  def apply(%__MODULE__{} = r, %Events.AdapterRevoked{} = e),
    do: %{r | adapters: Map.delete(r.adapters, e.adapter)}

  def apply(%__MODULE__{} = r, %Events.TimezoneSet{} = e), do: %{r | timezone: e.timezone}

  def apply(%__MODULE__{} = r, %Events.RootMismatchDetected{}), do: r
  def apply(%__MODULE__{} = r, %Events.RecordsRemoteSet{} = e), do: %{r | remote: e.url}

  # ---- helpers ----

  defp write_ok(c) do
    cond do
      c.file not in @files -> {:error, :file_unknown}
      not content_ok?(c.content) -> {:error, :content_invalid}
      not cites_ok?(c.cites) -> {:error, :cites_invalid}
      true -> :ok
    end
  end

  defp write_file(r, c, content) do
    cond do
      Map.get(r.files, c.file) == content ->
        []

      first_contact?(r) and actor_kind(c.actor) != "resident" ->
        {:error, :propose_instead}

      first_contact?(r) ->
        [soul_edit_applied(c, nil, content) | soul_events(r, c.file, c.content, c)]

      c.origin not in @origins ->
        {:error, :origin_invalid}

      true ->
        [seed_file_written(c, content) | soul_events(r, c.file, c.content, c)]
    end
  end

  defp seed_file_written(c, content) do
    %Events.SeedFileWritten{
      actor: c.actor,
      at: c.at,
      id: c.id,
      file: c.file,
      content: content,
      origin: c.origin,
      model: c.model,
      prompt: c.prompt
    }
  end

  defp soul_edit_applied(c, ref, content) do
    %Events.SoulEditApplied{
      actor: c.actor,
      at: c.at,
      id: c.id,
      ref: ref,
      file: c.file,
      content: content
    }
  end

  # The soul's words are stored without their markers, so a rendered
  # file written back is the same content and the numbers never enter
  # the log as text. A proposal keeps its markers until it is applied:
  # they are the witness's claims, and the resident reads them as such.
  defp soul_content("SOUL.md", content) when is_binary(content), do: SoulLines.strip(content)
  defp soul_content(_file, content), do: content

  # The soul lines' verdict on a write of `SOUL.md` (spec §6.17, P39):
  # each new paragraph mints a `soul` number and is written, a paragraph
  # claiming a line by its marker is reworded under that number, a
  # dropped line is retired, and the order is restated when it moved
  # (`SoulLines.diff/2` has the rules). Any other file
  # has no lines. The numbers are minted here rather than by `MintId`
  # because the write and its lines are one dispatch, and a replay must
  # reproduce every number from the stream alone.
  defp soul_events(%__MODULE__{} = r, "SOUL.md", content, c) do
    %{order: order, retired: retired} = SoulLines.diff(r.soul, SoulLines.marked(content))
    base = %{actor: c.actor, at: c.at, id: c.id, cites: c.cites || []}
    start = Map.get(r.sequences, "soul", 0)

    {events, _next, numbers} =
      Enum.reduce(order, {[], start, []}, fn
        {:kept, n}, {events, next, numbers} ->
          {events, next, [n | numbers]}

        {:reworded, n, text}, {events, next, numbers} ->
          reworded = struct!(Events.SoulLineReworded, Map.merge(base, %{number: n, text: text}))
          {[reworded | events], next, [n | numbers]}

        {:written, text}, {events, next, numbers} ->
          n = next + 1
          minted = %Events.IdMinted{actor: c.actor, at: c.at, id: c.id, kind: "soul", number: n}
          written = struct!(Events.SoulLineWritten, Map.merge(base, %{number: n, text: text}))
          {[written, minted | events], n, [n | numbers]}
      end)

    numbers = Enum.reverse(numbers)

    retirements =
      for n <- retired, do: %Events.SoulLineRetired{actor: c.actor, at: c.at, id: c.id, number: n}

    ordered =
      if numbers == Enum.map(r.soul, &elem(&1, 0)),
        do: [],
        else: [%Events.SoulLinesOrdered{actor: c.actor, at: c.at, id: c.id, numbers: numbers}]

    Enum.reverse(events) ++ retirements ++ ordered
  end

  defp soul_events(_r, _file, _content, _c), do: []

  defp cites_ok?(nil), do: true
  defp cites_ok?(cites) when is_list(cites), do: Enum.all?(cites, &(is_integer(&1) and &1 > 0))
  defp cites_ok?(_other), do: false

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

  # ---- the contract's and custody's helpers ----

  defp contract_proposed(c, version) do
    %Events.DyadContractProposed{
      actor: c.actor,
      at: c.at,
      note: c.note,
      id: c.id,
      version: version,
      terms: c.terms,
      prose: c.prose
    }
  end

  # A proposal is decided by the other party of the dyad, never its
  # proposer, and only while it is the open one.
  defp decidable(%__MODULE__{contract: %{open: open}} = r, c) do
    cond do
      not party?(r, c.actor) -> {:error, :not_a_party}
      is_nil(open) or open.version != c.version -> {:error, :no_such_proposal}
      open.by == c.actor.kind -> {:error, :own_proposal}
      true -> :ok
    end
  end

  defp party?(%__MODULE__{id: id}, %{kind: :resident, id: id}), do: true
  defp party?(%__MODULE__{} = r, %{kind: :witness} = actor), do: witness?(r, actor)
  defp party?(_r, _actor), do: false

  defp witness?(%__MODULE__{witness_account_id: id}, %{kind: :witness, id: id})
       when is_binary(id),
       do: true

  defp witness?(_r, _actor), do: false

  defp proposed?(%{kind: :witness, id: id}, to), do: id == to
  defp proposed?(_actor, _to), do: false

  defp terms_ok?(terms) when is_map(terms) do
    Enum.all?(terms, fn {k, v} -> is_binary(k) and k in @contract_terms and is_boolean(v) end)
  end

  defp terms_ok?(_terms), do: false

  defp prose_ok?(prose), do: is_binary(prose) and String.length(prose) <= @prose_limit
end
