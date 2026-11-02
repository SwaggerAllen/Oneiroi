defmodule Oneiroi.Kumbukumbu.Commands do
  @moduledoc "The conversation aggregate's commands."

  defmodule OpenSession do
    # `domain` (spec §6.3, P23): the room the session is in, a slug or
    # nil for the common room; retrieval respects it. `label` and
    # `runtime` name an adapter's conversation (kumbukumbu #40).
    use Oneiroi.Command,
      fields: [
        :id,
        :resident_id,
        :session_key,
        :kind,
        :adapter,
        :participants,
        :private,
        :domain,
        :label,
        :runtime
      ]
  end

  defmodule StartTurn do
    use Oneiroi.Command, fields: [:id, :resident_id, :session_key, :turn_ref]
  end

  defmodule CaptureTurn do
    use Oneiroi.Command,
      fields: [:id, :resident_id, :session_key, :turn_ref, :started_at, :messages]
  end

  defmodule RecordContext do
    use Oneiroi.Command, fields: [:id, :resident_id, :session_key, :turn_ref, :injections]
  end

  defmodule CompactSession do
    use Oneiroi.Command,
      fields: [:id, :resident_id, :session_key, :turn_ref, :through_sequence, :summary]
  end

  defmodule FailCapture do
    use Oneiroi.Command, fields: [:id, :resident_id, :session_key, :turn_ref, :reason]
  end

  defmodule ResolveCaptureFailure do
    use Oneiroi.Command,
      decision: true,
      fields: [:id, :resident_id, :session_key, :turn_ref, :how]
  end

  defmodule ShareSession do
    use Oneiroi.Command, decision: true, fields: [:id, :resident_id, :session_key]
  end
end
