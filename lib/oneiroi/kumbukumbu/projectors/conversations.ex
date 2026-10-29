defmodule Oneiroi.Kumbukumbu.Projectors.Conversations do
  @moduledoc "Folds the conversation streams into sessions, messages, capture failures and context injections."
  use Oneiroi.Projection, name: "kumbukumbu_conversations"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Kumbukumbu.Events
  alias Oneiroi.Kumbukumbu.Store.{Bookmark, CaptureFailure, ContextInjection, Message, Session}

  fold(%Events.SessionOpened{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :session,
      %Session{
        resident_id: e.resident_id,
        key: e.session_key,
        account_id: account_party(e.participants),
        kind: e.kind,
        adapter: e.adapter,
        participants: e.participants,
        opened_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key]
    )
  end)

  # The adapter contract's open turn (spec §8): the ref the next tool
  # calls are attributed to, cleared when a turn is captured.
  fold(%Events.TurnStarted{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :open_turn, from(s in Session, where: s.key == ^e.session_key),
      set: [open_turn_ref: e.turn_ref]
    )
  end)

  fold(%Events.TurnCaptured{} = e, metadata, fn multi ->
    # The event's position in the store orders the transcript (#18): under
    # a fixed clock every `sent_at` is equal, and the role sorted after it
    # put every assistant reply ahead of every user message.
    sequence = Map.get(metadata, :event_number, 0)

    # The rows take the session's account party, read once in the same
    # transaction rather than carried on every message.
    multi =
      Multi.run(multi, :party, fn repo, _changes ->
        {:ok, repo.one(from(s in Session, where: s.key == ^e.session_key, select: s.account_id))}
      end)

    e.messages
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {m, i}, multi ->
      Multi.insert(
        multi,
        {:message, i},
        fn %{party: party} ->
          %Message{
            resident_id: e.resident_id,
            session_key: e.session_key,
            sent_at: instant(field(m, :sent_at), e.at),
            hash: field(m, :hash),
            account_id: party,
            turn_ref: e.turn_ref,
            sequence: sequence,
            position: i,
            role: field(m, :role),
            actor_kind: m |> actor_field(:kind) |> to_string_or_nil(),
            actor_id: actor_field(m, :id),
            model: actor_field(m, :model),
            content: field(m, :content),
            refusal: field(m, :refusal) == true
          }
        end,
        on_conflict: :nothing,
        conflict_target: [:resident_id, :session_key, :sent_at, :hash]
      )
    end)
    |> Multi.update_all(
      :session_touched,
      from(s in Session, where: s.key == ^e.session_key),
      set: [last_turn_at: e.at],
      inc: [turns: 1]
    )
    |> Multi.update_all(
      :turn_closed,
      from(s in Session, where: s.key == ^e.session_key and s.open_turn_ref == ^e.turn_ref),
      set: [open_turn_ref: nil]
    )
  end)

  fold(%Events.ContextAssembled{} = e, _metadata, fn multi ->
    multi =
      Multi.run(multi, :party, fn repo, _changes ->
        {:ok, repo.one(from(s in Session, where: s.key == ^e.session_key, select: s.account_id))}
      end)

    e.injections
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {inj, i}, multi ->
      Multi.insert(
        multi,
        {:injection, i},
        fn %{party: party} ->
          %ContextInjection{
            resident_id: e.resident_id,
            turn_ref: e.turn_ref,
            position: i,
            account_id: party,
            session_key: e.session_key,
            label: field(inj, :label),
            tokens: field(inj, :tokens) || 0,
            reason: field(inj, :reason),
            text: field(inj, :text),
            at: e.at
          }
        end,
        on_conflict: :nothing,
        conflict_target: [:resident_id, :turn_ref, :position]
      )
    end)
    |> mark_indexed(e)
  end)

  fold(%Events.Compacted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :compacted,
      from(s in Session, where: s.key == ^e.session_key),
      set: [summary: e.summary, compacted_through: e.through_sequence]
    )
  end)

  fold(%Events.CaptureFailed{} = e, _metadata, fn multi ->
    multi
    |> Multi.run(:party, fn repo, _changes ->
      {:ok, repo.one(from(s in Session, where: s.key == ^e.session_key, select: s.account_id))}
    end)
    |> Multi.insert(
      :failure,
      fn %{party: party} ->
        %CaptureFailure{
          resident_id: e.resident_id,
          turn_ref: e.turn_ref,
          account_id: party,
          session_key: e.session_key,
          reason: e.reason,
          failed_at: e.at
        }
      end,
      on_conflict: [set: [reason: e.reason, failed_at: e.at, resolved_at: nil, how: nil]],
      conflict_target: [:resident_id, :turn_ref]
    )
  end)

  fold(%Events.CaptureFailureResolved{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :resolved,
      from(f in CaptureFailure, where: f.turn_ref == ^e.turn_ref),
      set: [resolved_at: e.at, how: e.how]
    )
  end)

  fold(%Events.SessionShared{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :shared, from(s in Session, where: s.key == ^e.session_key),
      set: [shared: true]
    )
  end)

  # Whether a bookmark was in the index this turn is derived from the last
  # `ContextAssembled` (spec §6.3): the index injection carries the
  # numbers it listed under `refs`, and each one's row takes the instant.
  defp mark_indexed(multi, e) do
    refs =
      e.injections
      |> Enum.flat_map(&List.wrap(field(&1, :refs)))
      |> Enum.map(&to_integer/1)
      |> Enum.reject(&is_nil/1)

    case refs do
      [] ->
        multi

      numbers ->
        Multi.update_all(
          multi,
          :indexed,
          from(b in Bookmark, where: b.number in ^numbers),
          set: [last_indexed_at: e.at]
        )
    end
  end

  defp to_integer(n) when is_integer(n), do: n

  defp to_integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp to_integer(_other), do: nil

  # The first account among the participants is the party the policy
  # keys on; a session with no account party (none exist yet: solo
  # sessions carry the steward's) would be the resident's alone.
  defp account_party(participants) when is_list(participants), do: List.first(participants)
  defp account_party(_other), do: nil

  # A message restored from the log has string keys; one built in process
  # has atoms. Both are one message.
  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp actor_field(map, key) do
    case field(map, :actor) do
      %{} = actor -> field(actor, key)
      _other -> nil
    end
  end

  # Always microsecond precision: the column is `utc_datetime_usec`, and
  # an adapter that sends `2026-10-26T12:00:00Z` once crashed this
  # projector on the cast, which took the whole event-handling tree down
  # with it. A wire instant is normalised here, never trusted.
  defp instant(%DateTime{} = at, _fallback), do: usec(at)

  defp instant(iso, fallback) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> usec(at)
      _error -> fallback
    end
  end

  defp instant(_other, fallback), do: fallback

  defp usec(%DateTime{microsecond: {us, _precision}} = at), do: %{at | microsecond: {us, 6}}

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp to_string_or_nil(string) when is_binary(string), do: string
end
