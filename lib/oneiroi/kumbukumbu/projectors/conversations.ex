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
        domain: Map.get(e, :domain),
        opened_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key]
    )
  end)

  # The adapter contract's open turn (spec §8): the ref the next tool
  # calls are attributed to, cleared when a turn is captured.
  fold(%Events.TurnStarted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :open_turn,
      from(s in Session, where: s.resident_id == ^e.resident_id and s.key == ^e.session_key),
      set: [open_turn_ref: e.turn_ref]
    )
  end)

  fold(%Events.TurnCaptured{} = e, metadata, fn multi ->
    # The event's position in the store orders the transcript (#18): under
    # a fixed clock every `sent_at` is equal, and the role sorted after it
    # put every assistant reply ahead of every user message.
    sequence = Map.get(metadata, :event_number, 0)

    # The rows take the session's account party, read once in the same
    # transaction rather than carried on every message. A private,
    # unshared session's messages are keyed to the resident instead, so
    # the account scope's policy answers none of them (kumbukumbu #28).
    multi =
      Multi.run(multi, :party, fn repo, _changes ->
        {:ok, party_of(repo, e.session_key, e.resident_id)}
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
      from(s in Session, where: s.resident_id == ^e.resident_id and s.key == ^e.session_key),
      set: [last_turn_at: e.at],
      inc: [turns: 1]
    )
    |> Multi.update_all(
      :turn_closed,
      from(s in Session,
        where:
          s.resident_id == ^e.resident_id and s.key == ^e.session_key and
            s.open_turn_ref == ^e.turn_ref
      ),
      set: [open_turn_ref: nil]
    )
  end)

  fold(%Events.ContextAssembled{} = e, _metadata, fn multi ->
    multi =
      Multi.run(multi, :party, fn repo, _changes ->
        {:ok,
         repo.one(
           from(s in Session,
             where: s.resident_id == ^e.resident_id and s.key == ^e.session_key,
             select: s.account_id
           )
         )}
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
      from(s in Session, where: s.resident_id == ^e.resident_id and s.key == ^e.session_key),
      set: [summary: e.summary, compacted_through: e.through_sequence]
    )
  end)

  fold(%Events.CaptureFailed{} = e, _metadata, fn multi ->
    multi
    |> Multi.run(:party, fn repo, _changes ->
      {:ok,
       repo.one(
         from(s in Session,
           where: s.resident_id == ^e.resident_id and s.key == ^e.session_key,
           select: s.account_id
         )
       )}
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
      from(f in CaptureFailure,
        where: f.resident_id == ^e.resident_id and f.turn_ref == ^e.turn_ref
      ),
      set: [resolved_at: e.at, how: e.how]
    )
  end)

  fold(%Events.SessionMadePrivate{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :private,
      from(s in Session, where: s.resident_id == ^e.resident_id and s.key == ^e.session_key),
      set: [private: true]
    )
  end)

  # Sharing keys the messages back to the account party, so a private
  # session the resident chose to share reads like any other.
  fold(%Events.SessionShared{} = e, _metadata, fn multi ->
    multi
    |> Multi.update_all(
      :shared,
      from(s in Session, where: s.resident_id == ^e.resident_id and s.key == ^e.session_key),
      set: [shared: true]
    )
    |> Multi.run(:rekey, fn repo, _changes ->
      case repo.one(
             from(s in Session,
               where: s.resident_id == ^e.resident_id and s.key == ^e.session_key,
               select: s.account_id
             )
           ) do
        nil ->
          {:ok, :none}

        account_id ->
          {:ok,
           repo.update_all(
             from(m in Message,
               where: m.resident_id == ^e.resident_id and m.session_key == ^e.session_key
             ),
             set: [account_id: account_id]
           )}
      end
    end)
  end)

  # A revealed wall at a transfer of custody (agathos-daimon #24): every
  # account-keyed row of the resident becomes the new witness's, which is
  # what "revealing it grants read on the earlier sessions" is (spec
  # §6.3): the earlier sessions are whoever's witnessed before, not only
  # the witness handing over, and a witness who handed over no longer
  # witnesses anything here. The first version moved the handing witness's
  # rows alone, so a session from two witnesses back stayed where it was.
  # Private sessions' messages are keyed to the resident and stay where
  # they are; their locked rows move with the rest.
  fold(%Oneiroi.AgathosDaimon.Events.EarlierSessionsRevealed{} = e, _metadata, fn multi ->
    Enum.reduce([Session, Message, CaptureFailure, ContextInjection], multi, fn schema, multi ->
      Multi.update_all(
        multi,
        {:reveal, schema},
        from(r in schema,
          where:
            r.resident_id == ^e.id and r.account_id != ^e.id and
              r.account_id != ^e.to_account_id
        ),
        set: [account_id: e.to_account_id]
      )
    end)
  end)

  # Whether a bookmark was in the index this turn is derived from the last
  # `ContextAssembled` (spec §6.3): the index injection carries the
  # numbers it listed under `refs`, and each one's row takes the instant.
  # The index's injection alone: the character section's refs are habit
  # numbers, and until the madeleine landed every injection's refs were
  # read as bookmarks, so habit #1 marked bookmark #1 as indexed. The
  # madeleine's refs mark a recall instead (#34), so one is not repeated.
  defp mark_indexed(multi, e) do
    multi
    |> mark(e, "index", :indexed, :last_indexed_at)
    |> mark(e, "madeleine", :recalled, :last_recalled_at)
  end

  defp mark(multi, e, label, name, column) do
    refs =
      e.injections
      |> Enum.filter(&(field(&1, :label) == label))
      |> Enum.flat_map(&List.wrap(field(&1, :refs)))
      |> Enum.map(&to_integer/1)
      |> Enum.reject(&is_nil/1)

    case refs do
      [] ->
        multi

      numbers ->
        Multi.update_all(
          multi,
          name,
          from(b in Bookmark, where: b.resident_id == ^e.resident_id and b.number in ^numbers),
          set: [{column, e.at}]
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
  # sessions carry the witness's) would be the resident's alone.
  defp account_party(participants) when is_list(participants), do: List.first(participants)
  defp account_party(_other), do: nil

  defp party_of(repo, session_key, resident_id) do
    case repo.one(
           from(s in Session,
             where: s.resident_id == ^resident_id and s.key == ^session_key,
             select: {s.account_id, s.private, s.shared}
           )
         ) do
      {_account, true, false} -> resident_id
      {account, _private, _shared} -> account
      nil -> nil
    end
  end

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
