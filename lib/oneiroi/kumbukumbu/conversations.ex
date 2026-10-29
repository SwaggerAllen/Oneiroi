defmodule Oneiroi.Kumbukumbu.Conversations do
  @moduledoc """
  Memory's service functions for conversations: the command edge, where
  session keys, turn refs, instants and content hashes are made, and the
  reads the transcript screen and the brain take.

  Reads for a steward run under the account's scope, which is the
  visibility rule itself (spec §6.3): an account sees the sessions it
  was party to and nothing else, enforced by the policy on the rows.
  The brain reads under the resident's scope and sees everything.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Router
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @doc "Opens a session of `kind` for the resident with the accounts party to it; returns its key."
  def open_session(resident_id, kind, adapter, participants, %Actor{} = actor)
      when is_list(participants) do
    key = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    with :ok <- dispatch_open(resident_id, key, kind, adapter, participants, actor),
         do: {:ok, key}
  end

  @doc "The main session between a resident and its steward, opened on first ask."
  def main_session(resident_id, account_id, %Actor{} = actor) do
    existing =
      Scope.account(account_id, fn ->
        Enum.find(Store.sessions(), &(&1.resident_id == resident_id and &1.kind == "main"))
      end)

    case existing do
      %{key: key} -> {:ok, key}
      nil -> open_session(resident_id, "main", "brain", [account_id], actor)
    end
  end

  def start_turn(resident_id, key, turn_ref, %Actor{} = actor) do
    command = %Commands.StartTurn{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref
    }

    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  @doc """
  Captures a turn: its messages, each a map with `role`, `content`,
  `sent_at` and `actor`, hashed here so the key the aggregate
  deduplicates on is the content's. `turn_ref` is the id the brain or
  the adapter gave the turn; `started_at` is when it began.
  """
  def capture(resident_id, key, turn_ref, %DateTime{} = started_at, messages, %Actor{} = actor)
      when is_list(messages) do
    command = %Commands.CaptureTurn{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      started_at: started_at,
      messages: Enum.map(messages, &wire_message/1)
    }

    case Router.dispatch(command) do
      {:ok, _events} -> :ok
      {:error, :no_such_session} -> {:error, Error.new(:kumbukumbu_no_such_session, key: key)}
      {:error, :empty_turn} -> {:error, Error.new(:kumbukumbu_empty_turn)}
      {:error, reason} -> {:error, reason}
    end
  end

  def record_context(resident_id, key, turn_ref, injections, %Actor{} = actor)
      when is_list(injections) do
    command = %Commands.RecordContext{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      injections: Enum.map(injections, &Map.take(&1, [:label, :tokens, :reason, :text, :refs]))
    }

    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  @doc "Records a compaction: the summary covering the session's messages through a store sequence (spec §5)."
  def compact(resident_id, key, turn_ref, through_sequence, summary, %Actor{} = actor) do
    command = %Commands.CompactSession{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      through_sequence: through_sequence,
      summary: summary
    }

    case Router.dispatch(command) do
      {:ok, _} -> :ok
      {:error, :summary_empty} -> {:error, Error.new(:kumbukumbu_summary_empty)}
      {:error, :no_such_session} -> {:error, Error.new(:kumbukumbu_no_such_session, key: key)}
      {:error, reason} -> {:error, reason}
    end
  end

  def fail_capture(resident_id, key, turn_ref, reason, %Actor{} = actor) when is_binary(reason) do
    command = %Commands.FailCapture{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      reason: reason
    }

    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  def resolve_failure(resident_id, key, turn_ref, how, note, %Actor{} = actor) do
    command = %Commands.ResolveCaptureFailure{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      how: how
    }

    case Router.dispatch(command) do
      {:ok, _} ->
        :ok

      {:error, :no_such_failure} ->
        {:error, Error.new(:kumbukumbu_no_such_failure, turn_ref: turn_ref)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def share_session(resident_id, key, note, %Actor{} = actor) do
    command = %Commands.ShareSession{
      actor: actor,
      at: Clock.now(),
      note: note,
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key
    }

    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  # ---- reads ----

  @doc "The sessions a scope sees: `{:account, id}` for a steward, `{:resident, id}` for the brain."
  def sessions(scope), do: Scope.run(scope, fn -> Store.sessions() end)

  def transcript(scope, key) do
    Scope.run(scope, fn ->
      case Store.session(key) do
        nil -> {:error, Error.new(:kumbukumbu_no_such_session, key: key)}
        session -> {:ok, session, Store.messages(key)}
      end
    end)
  end

  @doc "The live transcript: the last `count` messages since the session's compaction."
  def recent(resident_id, key, count),
    do: Scope.resident(resident_id, fn -> Store.recent_messages(key, count) end)

  @doc "The session and what compaction has not covered: the count of messages after it, and those messages."
  def uncompacted(resident_id, key) do
    Scope.resident(resident_id, fn ->
      case Store.session(key) do
        nil ->
          {:error, Error.new(:kumbukumbu_no_such_session, key: key)}

        s ->
          count = Store.messages_after(key, s.compacted_through)
          {:ok, s, count}
      end
    end)
  end

  @doc "Every message after the compaction, in order."
  def since_compaction(resident_id, key) do
    Scope.resident(resident_id, fn ->
      case Store.session(key) do
        nil -> []
        s -> key |> Store.messages() |> Enum.filter(&(&1.sequence > s.compacted_through))
      end
    end)
  end

  def search(scope, text, limit), do: Scope.run(scope, fn -> Store.search(text, limit) end)

  def failures(scope), do: Scope.run(scope, fn -> Store.open_failures() end)

  def injections(scope, turn_ref), do: Scope.run(scope, fn -> Store.injections(turn_ref) end)

  @doc "The sha256 of a message's content, hex: the key a message is stored under."
  @spec hash(String.t()) :: String.t()
  def hash(content) when is_binary(content),
    do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  @doc "A fresh turn ref."
  @spec turn_ref() :: String.t()
  def turn_ref, do: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "The aggregate id of a session's stream: `<resident_id>-<session_key>` under the `conversation-` prefix."
  @spec stream(String.t(), String.t()) :: String.t()
  def stream(resident_id, key), do: resident_id <> "-" <> key

  defp dispatch_open(resident_id, key, kind, adapter, participants, actor) do
    command = %Commands.OpenSession{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      kind: kind,
      adapter: adapter,
      participants: participants
    }

    case Router.dispatch(command) do
      {:ok, _} ->
        :ok

      {:error, :kind_invalid} ->
        {:error, Error.new(:kumbukumbu_kind_invalid, kind: kind, kinds: Conversation.kinds())}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wire_message(%{role: role, content: content} = m) when is_binary(content) do
    actor = Map.get(m, :actor) || Actor.platform()
    sent_at = Map.get(m, :sent_at) || Clock.now()

    %{
      role: Atom.to_string(role),
      content: content,
      sent_at: DateTime.to_iso8601(sent_at),
      hash: hash(content),
      actor: %{kind: Atom.to_string(actor.kind), id: actor.id, model: actor.model},
      refusal: Map.get(m, :refusal, false) == true
    }
  end
end
