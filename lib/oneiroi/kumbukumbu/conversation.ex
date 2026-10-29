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

  @doc "The session kinds a conversation may be; regression sessions are never captured (spec §6.4)."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  # ---- execute ----

  def execute(%__MODULE__{state: :absent}, %Commands.OpenSession{} = c) do
    if c.kind in @kinds do
      %Events.SessionOpened{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id,
        session_key: c.session_key,
        kind: c.kind,
        adapter: c.adapter,
        participants: c.participants
      }
    else
      {:error, :kind_invalid}
    end
  end

  # Opening an open session is the adapter saying hello again: no event.
  def execute(%__MODULE__{}, %Commands.OpenSession{}), do: []

  def execute(%__MODULE__{state: :absent}, _command), do: {:error, :no_such_session}

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
        {:error, :empty_turn}

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
        {:error, :summary_empty}

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
        {:error, :no_such_failure}

      c.how not in ["retried", "marked_lost"] ->
        {:error, :how_invalid}

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

  @doc "The idempotency key of a turn: when it started and the hash of its messages' hashes, in order."
  @spec turn_key(DateTime.t(), [map()]) :: {String.t(), String.t()}
  def turn_key(%DateTime{} = started_at, messages) do
    joined = Enum.map_join(messages, "\n", &(Map.get(&1, :hash) || Map.get(&1, "hash") || ""))

    {DateTime.to_iso8601(started_at),
     :crypto.hash(:sha256, joined) |> Base.encode16(case: :lower)}
  end
end
