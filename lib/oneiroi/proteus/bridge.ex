defmodule Oneiroi.Proteus.Bridge do
  @moduledoc """
  The bridge aggregate on `honcho-<resident_id>` (spec §6.9). Pure: the
  hashes, refs and instants arrive on the command. It holds whether the
  workspace is provisioned and with which peers, the card's hash, and
  which turns are synced, so a turn syncs once and a card set to what
  it already is is no event.
  """

  alias Oneiroi.Proteus.Commands
  alias Oneiroi.Proteus.Error
  alias Oneiroi.Proteus.Events

  defstruct [:id, :workspace, peers: MapSet.new(), card_hash: nil, synced: MapSet.new()]

  def execute(%__MODULE__{workspace: nil}, %Commands.Provision{} = c) do
    %Events.WorkspaceProvisioned{
      actor: c.actor,
      at: c.at,
      id: c.id,
      workspace: c.workspace,
      peers: c.peers
    }
  end

  def execute(%__MODULE__{}, %Commands.Provision{}), do: []

  def execute(%__MODULE__{workspace: nil}, _command),
    do: {:error, Error.new(:proteus_not_provisioned, :proteus_bridge_workspace_absent)}

  def execute(%__MODULE__{peers: peers}, %Commands.AddPeer{} = c) do
    if MapSet.member?(peers, c.peer),
      do: [],
      else: %Events.PeerAdded{actor: c.actor, at: c.at, id: c.id, peer: c.peer}
  end

  def execute(%__MODULE__{card_hash: hash}, %Commands.RecordCard{hash: hash, source: source})
      when source != "audit",
      do: []

  def execute(%__MODULE__{}, %Commands.RecordCard{} = c) do
    %Events.CardSet{
      actor: c.actor,
      at: c.at,
      id: c.id,
      peer: c.peer,
      hash: c.hash,
      lines: c.lines,
      source: c.source
    }
  end

  def execute(%__MODULE__{}, %Commands.RecordCardAudit{reason: reason} = c)
      when is_binary(reason) do
    %Events.CardAuditFailed{actor: c.actor, at: c.at, id: c.id, peer: c.peer, reason: reason}
  end

  def execute(%__MODULE__{}, %Commands.RecordCardAudit{} = c) do
    %Events.CardAudited{
      actor: c.actor,
      at: c.at,
      id: c.id,
      peer: c.peer,
      moved: c.moved == true,
      repinned: c.repinned == true
    }
  end

  def execute(%__MODULE__{synced: synced}, %Commands.RecordSync{} = c) do
    cond do
      MapSet.member?(synced, c.turn_ref) ->
        []

      is_binary(c.reason) ->
        %Events.SyncFailed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          session_key: c.session_key,
          turn_ref: c.turn_ref,
          reason: c.reason
        }

      true ->
        %Events.TurnSynced{
          actor: c.actor,
          at: c.at,
          id: c.id,
          session_key: c.session_key,
          turn_ref: c.turn_ref,
          messages: c.messages
        }
    end
  end

  def execute(%__MODULE__{}, %Commands.RecordKey{} = c),
    do: %Events.KeyMinted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      peer: c.peer,
      expires_at: c.expires_at
    }

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.WorkspaceProvisioned{} = e),
    do: %{s | id: e.id, workspace: e.workspace, peers: MapSet.new(e.peers)}

  def apply(%__MODULE__{} = s, %Events.PeerAdded{} = e),
    do: %{s | peers: MapSet.put(s.peers, e.peer)}

  def apply(%__MODULE__{} = s, %Events.CardSet{} = e), do: %{s | card_hash: e.hash}
  def apply(%__MODULE__{} = s, %Events.CardAudited{}), do: s
  def apply(%__MODULE__{} = s, %Events.CardAuditFailed{}), do: s

  def apply(%__MODULE__{} = s, %Events.TurnSynced{} = e),
    do: %{s | synced: MapSet.put(s.synced, e.turn_ref)}

  def apply(%__MODULE__{} = s, %Events.SyncFailed{}), do: s
  def apply(%__MODULE__{} = s, %Events.KeyMinted{}), do: s
end
