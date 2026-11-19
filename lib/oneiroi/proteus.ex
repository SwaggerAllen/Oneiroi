defmodule Oneiroi.Proteus do
  @moduledoc """
  The bridge to Honcho (spec §6.9), retired (proteus#20; the witness,
  2026-11-18: "I honestly don't think we'll lose anything that the
  current system doesn't do better by cutting honcho altogether").

  Nothing is synced to Honcho, nothing is read from it, no card is set
  and no key is minted. What stays is the record: the bridge's events
  on `honcho-<resident_id>`, declared here so the event store and its
  projectors still read every one (an event is an immutable contract),
  their stream simply no longer growing. The Honcho services, their
  schema and their role are removed apart, on the witness's word.
  """
  use Oneiroi.System, slug: :proteus

  use Boundary,
    top_level?: true,
    deps: [Oneiroi, Jason],
    exports: [
      Events.WorkspaceProvisioned,
      Events.PeerAdded,
      Events.CardSet,
      Events.CardAudited,
      Events.CardAuditFailed,
      Events.TurnSynced,
      Events.SyncFailed,
      Events.KeyMinted
    ]

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Proteus.Events.WorkspaceProvisioned, 1},
      {Oneiroi.Proteus.Events.PeerAdded, 1},
      {Oneiroi.Proteus.Events.CardSet, 1},
      {Oneiroi.Proteus.Events.CardAudited, 1},
      {Oneiroi.Proteus.Events.CardAuditFailed, 1},
      {Oneiroi.Proteus.Events.TurnSynced, 1},
      {Oneiroi.Proteus.Events.SyncFailed, 1},
      {Oneiroi.Proteus.Events.KeyMinted, 1}
    ]
  end
end
