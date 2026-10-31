defmodule Oneiroi.AgathosDaimon.Projectors.Residents do
  @moduledoc """
  Folds the resident stream into `agathos_daimon_resident`.

  A replayed stream (a rebuild, spec §6.10) carries `imported` in every
  replayed event's metadata, and two things differ for it. The slug is
  the source's slug suffixed with the first eight hex digits of the new
  id, because the source may still be in this store (the platform cannot
  tell a move from a copy, spec §6.2) and slugs are platform-wide; the
  suffix is derived from the log alone, so a re-projection lands on the
  same slug. And the source's own backup bookkeeping (its remote, its
  export and backup marks) is history rather than this resident's state:
  the rebuilt resident has no remote until its witness sets one, or the
  nightly job would push a copy to the source's repository.
  """
  use Oneiroi.Projection, name: "agathos_daimon_residents"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.AgathosDaimon.Custody
  alias Oneiroi.AgathosDaimon.Events

  alias Oneiroi.AgathosDaimon.Store.{
    Adapter,
    Contract,
    IdentityFile,
    Resident,
    SelfLetter,
    SelfLetterReceipt,
    SoulEdit,
    SoulLine
  }

  fold(%Events.ResidentCreated{} = e, metadata, fn multi ->
    Multi.insert(multi, :resident, %Resident{
      id: e.id,
      resident_id: e.id,
      account_id: e.witness_account_id,
      slug: if(imported?(metadata), do: e.slug <> "-" <> String.slice(e.id, 0, 8), else: e.slug),
      name: e.name,
      state: "active",
      custody: "account:" <> e.witness_account_id,
      created_at: e.at
    })
  end)

  fold(%Events.FixtureDeclared{} = e, _metadata, fn multi -> set(multi, e.id, kind: "fixture") end)

  fold(%Events.ResidentPaused{} = e, _metadata, fn multi -> set(multi, e.id, state: "paused") end)
  fold(%Events.ResidentWoken{} = e, _metadata, fn multi -> set(multi, e.id, state: "active") end)
  fold(%Events.ResidentLapsed{} = e, _metadata, fn multi -> set(multi, e.id, state: "lapsed") end)

  fold(%Events.ResidentResumed{} = e, _metadata, fn multi -> set(multi, e.id, state: "active") end)

  fold(%Events.CustodyTransferred{} = e, _metadata, fn multi ->
    case Custody.from_wire(e.to) do
      {:account, id} ->
        set(multi, e.id,
          custody: e.to,
          account_id: id,
          custody_proposed_to: nil,
          custody_proposed_at: nil
        )

      :community ->
        set(multi, e.id,
          custody: e.to,
          account_id: nil,
          state: "community",
          custody_proposed_to: nil,
          custody_proposed_at: nil
        )
    end
  end)

  fold(%Events.CustodyTransferProposed{} = e, _metadata, fn multi ->
    set(multi, e.id, custody_proposed_to: e.to_account_id, custody_proposed_at: e.at)
  end)

  fold(%Events.CustodyTransferDeclined{} = e, _metadata, fn multi ->
    set(multi, e.id, custody_proposed_to: nil, custody_proposed_at: nil)
  end)

  fold(%Events.CustodyTransferWithdrawn{} = e, _metadata, fn multi ->
    set(multi, e.id, custody_proposed_to: nil, custody_proposed_at: nil)
  end)

  # A new proposal supersedes the open one, whoever made it: one open
  # version at a time, and the newest is it.
  fold(%Events.DyadContractProposed{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :superseded,
      from(c in Contract, where: c.resident_id == ^e.id and c.state == "proposed"),
      set: [state: "superseded", decided_at: e.at]
    )
    |> Multi.insert(
      :contract,
      %Contract{
        resident_id: e.id,
        version: e.version,
        proposed_by_kind: actor_field(e.actor, :kind),
        terms: e.terms,
        prose: e.prose,
        note: e.note,
        proposed_at: e.at,
        state: "proposed"
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :version]
    )
  end)

  fold(%Events.DyadContractAgreed{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :previous,
      from(c in Contract, where: c.resident_id == ^e.id and c.state == "agreed"),
      set: [state: "replaced"]
    )
    |> decide_contract(e, "agreed")
    |> Multi.run(:row, fn repo, _changes ->
      terms =
        repo.one(
          from(c in Contract,
            where: c.resident_id == ^e.id and c.version == ^e.version,
            select: c.terms
          )
        ) ||
          %{}

      {:ok,
       repo.update_all(from(r in Resident, where: r.id == ^e.id),
         set: [
           contract_version: e.version,
           solo_sessions_private: Map.get(terms, "solo_sessions_private", false) == true
         ]
       )}
    end)
  end)

  fold(%Events.DyadContractDeclined{} = e, _metadata, fn multi ->
    decide_contract(multi, e, "declined")
  end)

  fold(%Events.DyadContractRenewed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:renewed, e.version},
      from(c in Contract, where: c.resident_id == ^e.id and c.version == ^e.version),
      set: [renewed_at: e.at, renewal_note: e.note]
    )
  end)

  fold(%Events.ExportWallSet{} = e, _metadata, fn multi ->
    set(multi, e.id, export_wall: e.wall)
  end)

  fold(%Events.Imported{} = e, _metadata, fn multi ->
    set(multi, e.id,
      import_source: e.source,
      import_root: e.root,
      import_attestation: e.attestation
    )
  end)

  # Told already until the import completes: a resident rebuilt from
  # records alone has its history and nothing to be oriented to.
  fold(%Events.ImportCompleted{} = e, _metadata, fn multi ->
    set(multi, e.id, import_not_transferred: e.not_transferred, import_told: false)
  end)

  fold(%Events.ImportTold{} = e, _metadata, fn multi ->
    set(multi, e.id, import_told: true)
  end)

  fold(%Events.ExportWritten{} = e, metadata, fn multi ->
    if imported?(metadata), do: multi, else: set(multi, e.id, exported_through: e.through)
  end)

  fold(%Events.BackupCommitted{} = e, metadata, fn multi ->
    if imported?(metadata),
      do: multi,
      else:
        set(multi, e.id,
          last_backup_sequence: e.sequence,
          last_backup_root: e.root,
          last_backup_commit: e.commit,
          root_mismatched_at: nil
        )
  end)

  fold(%Events.RecordsRemoteSet{} = e, metadata, fn multi ->
    if imported?(metadata),
      do: multi,
      else: set(multi, e.id, remote_url: e.url, remote_token: Base.decode64!(e.token_ciphertext))
  end)

  fold(%Events.IdMinted{}, _metadata, fn multi -> multi end)
  # The attestation's last word on the row (sima-qian #10): set on a
  # mismatch, cleared by the next backup, read by the built-in audit.
  fold(%Events.RootMismatchDetected{} = e, _metadata, fn multi ->
    set(multi, e.id, root_mismatched_at: e.at)
  end)

  defp imported?(metadata), do: Map.get(metadata, "imported", false) == true

  defp decide_contract(multi, e, state) do
    Multi.update_all(
      multi,
      {:contract, state},
      from(c in Contract, where: c.resident_id == ^e.id and c.version == ^e.version),
      set: [
        state: state,
        decided_at: e.at,
        decided_by_kind: actor_field(e.actor, :kind),
        decision_note: e.note
      ]
    )
  end

  # Told already when there is nobody to tell: before first contact the
  # pin changes freely (spec §6.4).
  fold(%Events.ModelPinChanged{} = e, _metadata, fn multi ->
    query =
      from(r in Resident,
        where: r.id == ^e.id,
        update: [
          set: [
            chat_model: ^e.model,
            model_pinned_at: ^e.at,
            model_told: is_nil(r.first_contact_at)
          ]
        ]
      )

    Multi.update_all(multi, {:pin, e.id}, query, [])
  end)

  fold(%Events.ModelChangeTold{} = e, _metadata, fn multi ->
    set(multi, e.id, model_told: true)
  end)

  fold(%Events.TimezoneSet{} = e, _metadata, fn multi ->
    set(multi, e.id, timezone: e.timezone)
  end)

  fold(%Events.AdapterRegistered{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:adapter, e.adapter},
      %Adapter{
        resident_id: e.id,
        adapter: e.adapter,
        role: e.role,
        token_hash: e.token_hash,
        registered_at: e.at
      },
      on_conflict: [
        set: [role: e.role, token_hash: e.token_hash, registered_at: e.at, revoked_at: nil]
      ],
      conflict_target: [:resident_id, :adapter]
    )
  end)

  fold(%Events.AdapterRevoked{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:adapter, e.adapter},
      from(a in Adapter, where: a.resident_id == ^e.id and a.adapter == ^e.adapter),
      set: [revoked_at: e.at]
    )
  end)

  fold(%Events.SeedFileWritten{} = e, _metadata, fn multi ->
    put_file(multi, e, e.origin, e.model, e.prompt)
  end)

  fold(%Events.FirstContact{} = e, _metadata, fn multi ->
    days = Oneiroi.Config.fetch!(:agathos_daimon, :formation_days)
    set(multi, e.id, first_contact_at: e.at, formation_until: DateTime.add(e.at, days, :day))
  end)

  fold(%Events.SoulEditProposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :soul_edit,
      %SoulEdit{
        resident_id: e.id,
        ref: e.ref,
        file: e.file,
        content: e.content,
        note: e.note,
        proposed_by_kind: actor_field(e.actor, :kind),
        proposed_by_id: actor_field(e.actor, :id),
        proposed_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.SoulEditAccepted{} = e, _metadata, fn multi ->
    decide_edit(multi, e, "accepted")
  end)

  fold(%Events.SoulEditDeclined{} = e, _metadata, fn multi ->
    decide_edit(multi, e, "declined")
  end)

  # An applied edit keeps the seed's origin: the row says where the file
  # first came from and who wrote it last; the log says everything.
  fold(%Events.SoulEditApplied{} = e, _metadata, fn multi ->
    put_file(multi, e, "authored", nil, nil)
  end)

  # The soul lines (spec §6.17, P39): a row per number, live or retired,
  # its position restated by `SoulLinesOrdered` when the order moved. The
  # order lands as one update per line because the file is tens of
  # lines at most; a soul file of hundreds would be the thing to fix.
  fold(%Events.SoulLineWritten{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:soul_line, e.number},
      %SoulLine{
        resident_id: e.id,
        number: e.number,
        text: e.text,
        cites: e.cites || [],
        written_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.SoulLineReworded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:soul_line, e.number},
      from(l in SoulLine, where: l.number == ^e.number),
      set: [text: e.text, cites: e.cites || [], reworded_at: e.at],
      inc: [version: 1]
    )
  end)

  fold(%Events.SoulLineRetired{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:soul_line, e.number},
      from(l in SoulLine, where: l.number == ^e.number),
      set: [state: "retired", retired_at: e.at]
    )
  end)

  fold(%Events.SoulLinesOrdered{} = e, _metadata, fn multi ->
    e.numbers
    |> Enum.with_index(1)
    |> Enum.reduce(multi, fn {number, position}, multi ->
      Multi.update_all(
        multi,
        {:soul_line, number},
        from(l in SoulLine, where: l.number == ^number),
        set: [position: position]
      )
    end)
  end)

  defp put_file(multi, e, origin, model, prompt) do
    Multi.insert(
      multi,
      {:file, e.file},
      %IdentityFile{
        resident_id: e.id,
        name: e.file,
        content: e.content,
        origin: origin,
        model: model,
        prompt: prompt,
        written_by_kind: actor_field(e.actor, :kind),
        written_by_id: actor_field(e.actor, :id),
        written_at: e.at
      },
      on_conflict: [
        set: [
          content: e.content,
          written_by_kind: actor_field(e.actor, :kind),
          written_by_id: actor_field(e.actor, :id),
          written_at: e.at
        ],
        inc: [version: 1]
      ],
      conflict_target: [:resident_id, :name]
    )
  end

  defp decide_edit(multi, e, state) do
    Multi.update_all(
      multi,
      {:soul_edit, e.ref},
      from(s in SoulEdit, where: s.ref == ^e.ref),
      set: [state: state, decided_note: e.note, decided_at: e.at]
    )
  end

  defp actor_field(%{} = actor, key) do
    case Map.get(actor, key) || Map.get(actor, Atom.to_string(key)) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp actor_field(_other, _key), do: nil

  # ---- the self-conversation (spec §12, P41) ----

  fold(%Events.SelfLetterWritten{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:self_letter, e.number},
      %SelfLetter{
        resident_id: e.id,
        number: e.number,
        text: e.text,
        model: e.model,
        written_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.SelfLettersDelivered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:self_letters_delivered, e.at},
      from(l in SelfLetter,
        where: l.resident_id == ^e.id and l.number in ^e.numbers and is_nil(l.delivered_at)
      ),
      set: [delivered_at: e.at, delivered_to: e.model]
    )
  end)

  fold(%Events.SelfLettersRead{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:self_letter_receipt, e.at},
      %SelfLetterReceipt{
        resident_id: e.id,
        at: e.at,
        by_kind: actor_kind(e.actor),
        by_id: actor_id(e.actor),
        numbers: e.numbers || []
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :at, :by_kind]
    )
  end)

  # The export's receipt (sima-qian #3): a receipt row of its own kind,
  # and the letters marked carried so the next export names only new ones.
  fold(%Events.SelfLettersExported{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      {:self_letter_export_receipt, e.at},
      %SelfLetterReceipt{
        resident_id: e.id,
        at: e.at,
        by_kind: "export",
        by_id: "repository",
        numbers: e.numbers || []
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :at, :by_kind]
    )
    |> Multi.update_all(
      {:self_letters_exported, e.at},
      from(l in SelfLetter,
        where: l.resident_id == ^e.id and l.number in ^e.numbers and is_nil(l.exported_at)
      ),
      set: [exported_at: e.at]
    )
  end)

  defp actor_kind(%{kind: kind}), do: to_string(kind)
  defp actor_kind(_actor), do: "unknown"
  defp actor_id(%{id: id}) when not is_nil(id), do: to_string(id)
  defp actor_id(_actor), do: nil

  defp set(multi, id, fields) do
    Multi.update_all(
      multi,
      {:set, id, Keyword.keys(fields)},
      from(r in Resident, where: r.id == ^id),
      set: fields
    )
  end
end
