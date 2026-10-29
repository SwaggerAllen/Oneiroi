defmodule Oneiroi.Proteus.Events do
  @moduledoc """
  The bridge stream's events, version 1 (spec §3.1, §6.9):
  `honcho-<resident_id>`, one per resident. What the bridge did and when;
  never what Honcho holds, which is Honcho's, and never a key.
  """

  defmodule WorkspaceProvisioned do
    use Oneiroi.Event, version: 1, fields: [:id, :workspace, :peers]
  end

  defmodule PeerAdded do
    use Oneiroi.Event, version: 1, fields: [:id, :peer]
  end

  defmodule CardSet do
    # The card comes from git, always (spec §6.9): the hash of what was
    # set and where the set came from (commit, audit, provision).
    use Oneiroi.Event, version: 1, fields: [:id, :peer, :hash, :lines, :source]
  end

  defmodule CardAudited do
    # The weekly check: whether a dream moved the card, and whether it
    # was pinned back.
    use Oneiroi.Event, version: 1, fields: [:id, :peer, :moved, :repinned]
  end

  defmodule CardAuditFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :peer, :reason]
  end

  defmodule TurnSynced do
    use Oneiroi.Event, version: 1, fields: [:id, :session_key, :turn_ref, :messages]
  end

  defmodule SyncFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :session_key, :turn_ref, :reason]
  end

  defmodule KeyMinted do
    # The fact of a key, never the key: for a hands runtime (P3).
    use Oneiroi.Event, version: 1, fields: [:id, :peer, :expires_at], instants: [:expires_at]
  end
end
