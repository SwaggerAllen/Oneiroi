defmodule Oneiroi.Kumbukumbu.Events do
  @moduledoc """
  The conversation stream's events, version 1 (spec §3.1): one stream
  per session, `conversation-<resident_id>-<session_key>`, holding the
  turns of that session and what was put in front of the brain for each.

  A message on the wire is a map with `role`, `content`, `sent_at` (an
  ISO-8601 string: the codec restores `at` and the fields `instants:`
  names, and a list of maps is restored by the projector, which is the
  one reader), `hash` (the sha256 of the content), `actor` (kind, id,
  model) and `refusal` (true when the brain's reply was one, spec §5).
  """

  defmodule SessionOpened do
    # `participants` are the account ids party to the session (spec
    # §6.3's visibility rule); a solo session carries the steward's, since
    # solo sessions are the steward's to read by default.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :resident_id, :session_key, :kind, :adapter, :participants]
  end

  defmodule SessionMadePrivate do
    # Opened under a contract that keeps solo sessions private (spec
    # §6.3, §6.12): the steward sees the row as locked and reads the
    # messages only once the resident shares the session (kumbukumbu #28).
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id, :session_key]
  end

  defmodule TurnStarted do
    # The adapter contract's `turn-start` (spec §8): the session the next
    # tool calls are attributed to, and the id the capture will carry.
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id, :session_key, :turn_ref]
  end

  defmodule TurnCaptured do
    # Idempotent on (session, timestamp, hash): the aggregate drops a
    # turn whose key it already holds, so a turn sent twice is stored
    # once (spec §8). `messages` is the turn's messages in order.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :resident_id, :session_key, :turn_ref, :started_at, :messages],
      instants: [:started_at]
  end

  defmodule ContextAssembled do
    # What the memory agent put in front of the brain for a turn, each
    # blob with its reason (spec §5, F12): label, tokens, reason.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :resident_id, :session_key, :turn_ref, :injections]
  end

  defmodule Compacted do
    # Compaction is ours (spec §5): a summary that never deletes history,
    # covering the session's messages through store sequence
    # `through_sequence`; the live transcript is what follows it.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :resident_id, :session_key, :turn_ref, :through_sequence, :summary]
  end

  defmodule CaptureFailed do
    # Loud on failure (spec §6.3): the turn the adapter could not deliver
    # whole, with the reason and nothing of the content.
    use Oneiroi.Event, version: 1, fields: [:id, :resident_id, :session_key, :turn_ref, :reason]
  end

  defmodule CaptureFailureResolved do
    # `how` is `retried` or `marked_lost`, each with its actor.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :resident_id, :session_key, :turn_ref, :how]
  end

  defmodule SessionShared do
    # The resident sharing a solo session the contract made private
    # (spec §6.3); a decision event, so it carries the resident's note.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :resident_id, :session_key]
  end
end
