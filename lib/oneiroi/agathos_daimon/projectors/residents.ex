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
  the rebuilt resident has no remote until its steward sets one, or the
  nightly job would push a copy to the source's repository.
  """
  use Oneiroi.Projection, name: "agathos_daimon_residents"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.AgathosDaimon.Custody
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Store.Resident

  fold(%Events.ResidentCreated{} = e, metadata, fn multi ->
    Multi.insert(multi, :resident, %Resident{
      id: e.id,
      resident_id: e.id,
      account_id: e.steward_account_id,
      slug: if(imported?(metadata), do: e.slug <> "-" <> String.slice(e.id, 0, 8), else: e.slug),
      name: e.name,
      state: "active",
      custody: "account:" <> e.steward_account_id,
      created_at: e.at
    })
  end)

  fold(%Events.ResidentPaused{} = e, _metadata, fn multi -> set(multi, e.id, state: "paused") end)
  fold(%Events.ResidentWoken{} = e, _metadata, fn multi -> set(multi, e.id, state: "active") end)

  fold(%Events.CustodyTransferred{} = e, _metadata, fn multi ->
    case Custody.from_wire(e.to) do
      {:account, id} -> set(multi, e.id, custody: e.to, account_id: id)
      :community -> set(multi, e.id, custody: e.to, account_id: nil, state: "community")
    end
  end)

  fold(%Events.ExportWallSet{} = e, _metadata, fn multi ->
    set(multi, e.id, export_wall: e.wall)
  end)

  fold(%Events.Imported{} = e, _metadata, fn multi ->
    set(multi, e.id, import_source: e.source, import_root: e.root)
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
          last_backup_commit: e.commit
        )
  end)

  fold(%Events.RecordsRemoteSet{} = e, metadata, fn multi ->
    if imported?(metadata),
      do: multi,
      else: set(multi, e.id, remote_url: e.url, remote_token: Base.decode64!(e.token_ciphertext))
  end)

  fold(%Events.IdMinted{}, _metadata, fn multi -> multi end)
  fold(%Events.RootMismatchDetected{}, _metadata, fn multi -> multi end)

  defp imported?(metadata), do: Map.get(metadata, "imported", false) == true

  defp set(multi, id, fields) do
    Multi.update_all(
      multi,
      {:set, id, Keyword.keys(fields)},
      from(r in Resident, where: r.id == ^id),
      set: fields
    )
  end
end
