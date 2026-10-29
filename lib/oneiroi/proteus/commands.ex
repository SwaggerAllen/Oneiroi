defmodule Oneiroi.Proteus.Commands do
  @moduledoc "The bridge aggregate's commands; `id` is the resident's id."

  defmodule Provision do
    use Oneiroi.Command, fields: [:id, :workspace, :peers]
  end

  defmodule AddPeer do
    use Oneiroi.Command, fields: [:id, :peer]
  end

  defmodule RecordCard do
    use Oneiroi.Command, fields: [:id, :peer, :hash, :lines, :source]
  end

  defmodule RecordCardAudit do
    use Oneiroi.Command, fields: [:id, :peer, :moved, :repinned, :reason]
  end

  defmodule RecordSync do
    use Oneiroi.Command, fields: [:id, :session_key, :turn_ref, :messages, :reason]
  end

  defmodule RecordKey do
    use Oneiroi.Command, fields: [:id, :peer, :expires_at]
  end
end
