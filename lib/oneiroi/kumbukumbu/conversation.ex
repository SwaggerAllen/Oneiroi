defmodule Oneiroi.Kumbukumbu.Conversation do
  @moduledoc """
  The conversation aggregate on `conversation-<resident_id>-<session_key>`
  (spec §3.1). Pure (conventions §6): the instant, the turn's ref and
  every message's hash arrive on the command.

  Idempotency lives here. The aggregate keeps the keys of the turns it
  has captured, `(started_at, hash of the messages)`, and a capture whose
  key it already holds produces no event: an adapter that spools and
  retries sends a turn twice and the log holds it once (spec §8).
  """

  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Events

  defstruct [
    :id,
    :session_key,
    :kind,
    state: :absent,
    turns: MapSet.new(),
    started: MapSet.new(),
    failures: %{},
    compacted_through: 0
  ]

  @kinds ~w(main free_time hands)
  # A session carried from another platform by an import (kumbukumbu
  # #37): accepted here, opened only through `open_imported/4`, never by
  # a client, and read by no nightly pass, because it was judged where
  # it was said.
  @imported "imported"
  # A domain is a slug the witness names at the session's opening (spec
  # §6.3, P23): the room, and the common room when nil.
  @domain ~r/\A[a-z][a-z0-9-]{1,31}\z/

  @doc "The session kinds a conversation may be; regression sessions are never captured (spec §6.4)."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "The kind of a session an import carried from another platform."
  @spec imported() :: String.t()
  def imported, do: @imported

  # ---- execute ----

  def execute(%__MODULE__{state: :absent}, %Commands.OpenSession{} = c) do
    cond do
      c.kind not in [@imported | @kinds] ->
        {:error,
         Error.new(:kumbukumbu_kind_invalid, :kumbukumbu_conversation_open_kind_invalid,
           kind: c.kind,
           kinds: @kinds
         )}

      not domain_ok?(c.domain) ->
        {:error,
         Error.new(:kumbukumbu_domain_invalid, :kumbukumbu_conversation_open_domain_invalid,
           domain: c.domain
         )}

      true ->
        open(c)
    end
  end

  # Opening an open session is the adapter saying hello again: no event.
  def execute(%__MODULE__{}, %Commands.OpenSession{}), do: []

  def execute(%__MODULE__{state: :absent}, command),
    do:
      {:error,
       Error.new(:kumbukumbu_no_such_session, :kumbukumbu_conversation_session_absent,
         key: Map.get(command, :session_key)
       )}

  def execute(%__MODULE__{started: started}, %Commands.StartTurn{} = c) do
    if MapSet.member?(started, c.turn_ref),
      do: [],
      else: %Events.TurnStarted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id,
        session_key: c.session_key,
        turn_ref: c.turn_ref
      }
  end

  def execute(%__MODULE__{turns: turns}, %Commands.CaptureTurn{} = c) do
    cond do
      c.messages == [] ->
        {:error,
         Error.new(:kumbukumbu_empty_turn, :kumbukumbu_conversation_capture_empty,
           turn_ref: c.turn_ref
         )}

      MapSet.member?(turns, turn_key(c.started_at, c.messages)) ->
        []

      true ->
        %Events.TurnCaptured{
          actor: c.actor,
          at: c.at,
          id: c.id,
          resident_id: c.resident_id,
          session_key: c.session_key,
          turn_ref: c.turn_ref,
          started_at: c.started_at,
          messages: c.messages
        }
    end
  end

  def execute(%__MODULE__{}, %Commands.RecordContext{} = c) do
    %Events.ContextAssembled{
      actor: c.actor,
      at: c.at,
      id: c.id,
      resident_id: c.resident_id,
      session_key: c.session_key,
      turn_ref: c.turn_ref,
      injections: c.injections
    }
  end

  # A summary covering nothing new is no event: the brain that compacts
  # twice over the same messages leaves one record.
  def execute(%__MODULE__{compacted_through: through}, %Commands.CompactSession{} = c) do
    cond do
      not is_integer(c.through_sequence) or c.through_sequence <= through ->
        []

      not is_binary(c.summary) or String.trim(c.summary) == "" ->
        {:error,
         Error.new(:kumbukumbu_summary_empty, :kumbukumbu_conversation_compact_summary_empty,
           key: c.session_key
         )}

      true ->
        %Events.Compacted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          resident_id: c.resident_id,
          session_key: c.session_key,
          turn_ref: c.turn_ref,
          through_sequence: c.through_sequence,
          summary: c.summary
        }
    end
  end

  def execute(%__MODULE__{}, %Commands.FailCapture{} = c) do
    %Events.CaptureFailed{
      actor: c.actor,
      at: c.at,
      id: c.id,
      resident_id: c.resident_id,
      session_key: c.session_key,
      turn_ref: c.turn_ref,
      reason: c.reason
    }
  end

  def execute(%__MODULE__{failures: failures}, %Commands.ResolveCaptureFailure{} = c) do
    cond do
      not Map.has_key?(failures, c.turn_ref) ->
        {:error,
         Error.new(:kumbukumbu_no_such_failure, :kumbukumbu_conversation_resolve_failure_absent,
           turn_ref: c.turn_ref
         )}

      c.how not in ["retried", "marked_lost"] ->
        {:error,
         Error.new(:kumbukumbu_how_invalid, :kumbukumbu_conversation_resolve_how_invalid,
           turn_ref: c.turn_ref
         )}

      true ->
        %Events.CaptureFailureResolved{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          resident_id: c.resident_id,
          session_key: c.session_key,
          turn_ref: c.turn_ref,
          how: c.how
        }
    end
  end

  def execute(%__MODULE__{}, %Commands.ShareSession{} = c),
    do: %Events.SessionShared{
      actor: c.actor,
      at: c.at,
      note: c.note,
      id: c.id,
      resident_id: c.resident_id,
      session_key: c.session_key
    }

  defp domain_ok?(nil), do: true
  defp domain_ok?(domain) when is_binary(domain), do: Regex.match?(@domain, domain)
  defp domain_ok?(_other), do: false

  defp open(c) do
    opened = %Events.SessionOpened{
      actor: c.actor,
      at: c.at,
      id: c.id,
      resident_id: c.resident_id,
      session_key: c.session_key,
      kind: c.kind,
      adapter: c.adapter,
      participants: c.participants,
      domain: c.domain
    }

    if c.private == true,
      do: [
        opened,
        %Events.SessionMadePrivate{
          actor: c.actor,
          at: c.at,
          id: c.id,
          resident_id: c.resident_id,
          session_key: c.session_key
        }
      ],
      else: opened
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.SessionOpened{} = e),
    do: %{s | id: e.id, session_key: e.session_key, kind: e.kind, state: :open}

  def apply(%__MODULE__{} = s, %Events.TurnStarted{} = e),
    do: %{s | started: MapSet.put(s.started, e.turn_ref)}

  def apply(%__MODULE__{} = s, %Events.TurnCaptured{} = e) do
    %{
      s
      | turns: MapSet.put(s.turns, turn_key(e.started_at, e.messages)),
        failures: Map.delete(s.failures, e.turn_ref)
    }
  end

  def apply(%__MODULE__{} = s, %Events.ContextAssembled{}), do: s

  def apply(%__MODULE__{} = s, %Events.Compacted{} = e),
    do: %{s | compacted_through: e.through_sequence}

  def apply(%__MODULE__{} = s, %Events.CaptureFailed{} = e),
    do: %{s | failures: Map.put(s.failures, e.turn_ref, e.reason)}

  def apply(%__MODULE__{} = s, %Events.CaptureFailureResolved{} = e),
    do: %{s | failures: Map.delete(s.failures, e.turn_ref)}

  def apply(%__MODULE__{} = s, %Events.SessionShared{}), do: s
  def apply(%__MODULE__{} = s, %Events.SessionMadePrivate{}), do: s

  @doc "The idempotency key of a turn: when it started and the hash of its messages' hashes, in order."
  @spec turn_key(DateTime.t(), [map()]) :: {String.t(), String.t()}
  def turn_key(%DateTime{} = started_at, messages) do
    joined = Enum.map_join(messages, "\n", &(Map.get(&1, :hash) || Map.get(&1, "hash") || ""))

    {DateTime.to_iso8601(started_at),
     :crypto.hash(:sha256, joined) |> Base.encode16(case: :lower)}
  end
end
