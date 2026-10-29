defmodule Oneiroi.Kumbukumbu.Projectors.Conversations do
  @moduledoc "Folds the conversation streams into sessions, messages, capture failures and context injections."
  use Oneiroi.Projection, name: "kumbukumbu_conversations"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Kumbukumbu.Events
  alias Oneiroi.Kumbukumbu.Store.{CaptureFailure, ContextInjection, Message, Session}

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

  fold(%Events.TurnStarted{}, _metadata, fn multi -> multi end)

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
            at: e.at
          }
        end,
        on_conflict: :nothing,
        conflict_target: [:resident_id, :turn_ref, :position]
      )
    end)
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

  defp instant(%DateTime{} = at, _fallback), do: at

  defp instant(iso, fallback) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _error -> fallback
    end
  end

  defp instant(_other, fallback), do: fallback

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp to_string_or_nil(string) when is_binary(string), do: string
end
