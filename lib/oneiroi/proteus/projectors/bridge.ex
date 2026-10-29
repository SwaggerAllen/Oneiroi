defmodule Oneiroi.Proteus.Projectors.Bridge do
  @moduledoc "Folds the bridge streams into the bridge row and the syncs."
  use Oneiroi.Projection, name: "proteus_bridge"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Proteus.Events
  alias Oneiroi.Proteus.Store.{Bridge, Sync}

  fold(%Events.WorkspaceProvisioned{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :bridge,
      %Bridge{resident_id: e.id, workspace: e.workspace, peers: e.peers, provisioned_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id]
    )
  end)

  fold(%Events.PeerAdded{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :peer, from(b in Bridge, where: b.resident_id == ^e.id),
      push: [peers: e.peer]
    )
  end)

  fold(%Events.CardSet{} = e, _metadata, fn multi ->
    set(multi, e.id,
      card_hash: e.hash,
      card_lines: e.lines,
      card_source: e.source,
      card_set_at: e.at
    )
  end)

  fold(%Events.CardAudited{} = e, _metadata, fn multi ->
    set(multi, e.id, last_audit_at: e.at, last_audit_moved: e.moved, last_audit_reason: nil)
  end)

  fold(%Events.CardAuditFailed{} = e, _metadata, fn multi ->
    set(multi, e.id, last_audit_at: e.at, last_audit_moved: nil, last_audit_reason: e.reason)
  end)

  fold(%Events.TurnSynced{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :sync,
      %Sync{
        resident_id: e.id,
        turn_ref: e.turn_ref,
        session_key: e.session_key,
        messages: e.messages,
        outcome: "synced",
        at: e.at
      },
      # A turn that failed to sync and then synced is one row, synced.
      on_conflict: [set: [outcome: "synced", reason: nil, messages: e.messages, at: e.at]],
      conflict_target: [:resident_id, :turn_ref]
    )
    |> Multi.update_all(:count, from(b in Bridge, where: b.resident_id == ^e.id),
      inc: [syncs: 1],
      set: [last_sync_at: e.at]
    )
  end)

  fold(%Events.SyncFailed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :sync,
      %Sync{
        resident_id: e.id,
        turn_ref: e.turn_ref,
        session_key: e.session_key,
        messages: 0,
        outcome: "failed",
        reason: e.reason,
        at: e.at
      },
      on_conflict: [set: [outcome: "failed", reason: e.reason, at: e.at]],
      conflict_target: [:resident_id, :turn_ref]
    )
  end)

  fold(%Events.KeyMinted{}, _metadata, fn multi -> multi end)

  defp set(multi, id, fields) do
    Multi.update_all(multi, {:set, fields}, from(b in Bridge, where: b.resident_id == ^id),
      set: fields
    )
  end
end
