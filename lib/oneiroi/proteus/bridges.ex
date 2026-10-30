defmodule Oneiroi.Proteus.Bridges do
  @moduledoc """
  The bridge's service functions (spec §6.9): provisioning the
  workspace and peers, the card from git, the sync of each captured
  turn, the context the brain reads, the weekly card audit, and keys
  for a hands runtime. Every call goes through the port with the
  workspace named; the workspace is the resident's id.

  A failure at Honcho is recorded on the bridge stream and returned;
  it is never the turn's to fail on, which is why the brain calls
  `sync_turn/5` and goes on either way.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Proteus.Commands
  alias Oneiroi.Proteus.Error
  alias Oneiroi.Proteus.Router
  alias Oneiroi.Proteus.Store
  alias Oneiroi.Scope

  @card_line_limit 300

  # ---- peers ----

  @doc "The resident's peer name in its workspace."
  def resident_peer(resident_id), do: "resident-" <> resident_id

  @doc "A witness's peer name."
  def witness_peer(account_id), do: "witness-" <> account_id

  # ---- provisioning ----

  @doc "Provisions the workspace with the resident's peer and the witness's, once; sets the card from git."
  def provision(resident_id, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id) do
      peers = [resident_peer(resident_id), witness_peer(row.account_id)]
      instructions = AgathosDaimon.custom_instructions(resident_id)

      with :ok <- port().ensure_workspace(resident_id),
           :ok <- ensure_peers(resident_id, peers, instructions),
           {:ok, _} <-
             dispatch(%Commands.Provision{
               actor: actor,
               at: Clock.now(),
               id: resident_id,
               workspace: resident_id,
               peers: peers
             }),
           {:ok, _} <- set_card(resident_id, "provision", actor) do
        :ok
      else
        {:error, reason} -> {:error, failure(reason)}
      end
    end
  end

  defp ensure_peers(resident_id, peers, instructions) do
    Enum.reduce_while(peers, :ok, fn peer, :ok ->
      case port().ensure_peer(resident_id, peer, %{custom_instructions: instructions}) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Adds a witness's peer when a session names an account the workspace has not met."
  def ensure_witness(resident_id, account_id, %Actor{} = actor) do
    case bridge(resident_id) do
      nil ->
        provision(resident_id, actor)

      %{peers: peers} = row ->
        add_witness(row, resident_id, witness_peer(account_id), peers, actor)
    end
  end

  defp add_witness(row, resident_id, peer, peers, actor) do
    if peer in peers, do: :ok, else: add_peer(row, resident_id, peer, actor)
  end

  defp add_peer(row, resident_id, peer, actor) do
    instructions = AgathosDaimon.custom_instructions(resident_id)

    with :ok <- port().ensure_peer(row.workspace, peer, %{custom_instructions: instructions}),
         {:ok, _} <-
           dispatch(%Commands.AddPeer{actor: actor, at: Clock.now(), id: resident_id, peer: peer}) do
      :ok
    else
      {:error, reason} -> {:error, failure(reason)}
    end
  end

  # ---- the card ----

  @doc """
  The card from git (spec §6.9): the soul and identity files as written,
  one line per paragraph, each cut at #{@card_line_limit} characters.
  Never from conversation.
  """
  @spec card(String.t()) :: [String.t()]
  def card(resident_id) do
    resident_id
    |> AgathosDaimon.identity_context()
    |> Enum.filter(fn {name, _} -> name in ["SOUL.md", "IDENTITY.md"] end)
    |> Enum.flat_map(fn {_name, content} ->
      # A heading names a file, not the resident; the paragraphs are the card.
      content
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(&(&1 |> String.replace(~r/\s+/, " ") |> String.slice(0, @card_line_limit)))
    end)
  end

  @doc "Sets the card at Honcho from git and records it; `source` is commit, audit or provision. No event when unchanged."
  def set_card(resident_id, source, %Actor{} = actor) do
    lines = card(resident_id)
    hash = hash(lines)
    peer = resident_peer(resident_id)

    with :ok <- port().set_card(resident_id, peer, lines),
         {:ok, events} <-
           dispatch(%Commands.RecordCard{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             peer: peer,
             hash: hash,
             lines: length(lines),
             source: source
           }) do
      {:ok, if(events == [], do: :unchanged, else: :set)}
    else
      {:error, reason} -> {:error, failure(reason)}
    end
  end

  @doc "The weekly audit: if a dream moved the card, pin it back from git; recorded either way."
  def audit_card(resident_id, %Actor{} = actor) do
    peer = resident_peer(resident_id)
    expected = card(resident_id)

    outcome =
      case port().get_card(resident_id, peer) do
        {:ok, ^expected} -> {:ok, false, false}
        {:ok, _moved} -> repin(resident_id, actor)
        {:error, reason} -> {:error, reason}
      end

    case outcome do
      {:ok, moved, repinned} ->
        command = %Commands.RecordCardAudit{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          peer: peer,
          moved: moved,
          repinned: repinned,
          reason: nil
        }

        with {:ok, _} <- dispatch(command), do: {:ok, %{moved: moved, repinned: repinned}}

      {:error, reason} ->
        command = %Commands.RecordCardAudit{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          peer: peer,
          reason: reason_text(reason)
        }

        with {:ok, _} <- dispatch(command), do: {:error, failure(reason)}
    end
  end

  defp repin(resident_id, actor) do
    case set_card(resident_id, "audit", actor) do
      {:ok, _} -> {:ok, true, true}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---- the sync ----

  @doc """
  Sends a captured turn's user and assistant messages to Honcho as the
  witness's and the resident's peers, once per turn, provisioning on the
  first; a failure is recorded and returned, never raised.
  """
  def sync_turn(resident_id, session_key, turn_ref, messages, %Actor{} = actor) do
    with :ok <- not_synced(resident_id, turn_ref),
         :ok <- provisioned(resident_id, messages, actor),
         sent = Enum.flat_map(messages, &peer_message(&1, resident_id)),
         :ok <-
           port().ensure_session(
             resident_id,
             session_key,
             sent |> Enum.map(& &1.peer) |> Enum.uniq()
           ),
         :ok <- port().add_messages(resident_id, session_key, sent),
         {:ok, _} <- record_sync(resident_id, session_key, turn_ref, length(sent), nil, actor) do
      :ok
    else
      :already ->
        :ok

      {:error, reason} ->
        record_sync(resident_id, session_key, turn_ref, 0, reason_text(reason), actor)
        {:error, failure(reason)}
    end
  end

  # Once per turn is the aggregate's rule, but the aggregate decides after
  # the messages are sent: the first version sent a retried turn twice
  # and recorded it once. The test that counts Honcho's messages found it.
  defp not_synced(resident_id, turn_ref) do
    case Enum.find(syncs(resident_id, 1_000), &(&1.turn_ref == turn_ref)) do
      %{outcome: "synced"} -> :already
      _none_or_failed -> :ok
    end
  end

  defp provisioned(resident_id, messages, actor) do
    case bridge(resident_id) do
      nil -> provision(resident_id, actor)
      _row -> ensure_witnesses(resident_id, messages, actor)
    end
  end

  defp ensure_witnesses(resident_id, messages, actor) do
    messages
    |> Enum.filter(&(&1.actor.kind == :witness))
    |> Enum.map(& &1.actor.id)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn account_id, :ok ->
      case ensure_witness(resident_id, account_id, actor) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp peer_message(%{role: :user, actor: %{kind: :witness, id: account_id}} = m, _resident_id),
    do: [%{peer: witness_peer(account_id), content: m.content, created_at: m.sent_at}]

  defp peer_message(%{role: :assistant} = m, resident_id),
    do: [%{peer: resident_peer(resident_id), content: m.content, created_at: m.sent_at}]

  defp peer_message(_other, _resident_id), do: []

  defp record_sync(resident_id, session_key, turn_ref, count, reason, actor) do
    dispatch(%Commands.RecordSync{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      session_key: session_key,
      turn_ref: turn_ref,
      messages: count,
      reason: reason
    })
  end

  # ---- reads ----

  @doc "Honcho's context on the witness in the resident's eyes, within the token bound; empty when there is none or Honcho is down."
  @spec context(String.t()) :: String.t()
  def context(resident_id) do
    with %{peers: peers} <- bridge(resident_id),
         [witness | _] <- Enum.filter(peers, &String.starts_with?(&1, "witness-")),
         {:ok, text} <-
           port().context(
             resident_id,
             resident_peer(resident_id),
             witness,
             Config.fetch!(:proteus, :context_tokens)
           ) do
      String.trim(text)
    else
      _none -> ""
    end
  end

  @doc "What Honcho concluded about the witness in the resident's eyes, at most `limit`."
  def conclusions(resident_id, limit) do
    with %{peers: peers} <- bridge(resident_id),
         [witness | _] <- Enum.filter(peers, &String.starts_with?(&1, "witness-")) do
      port().conclusions(resident_id, resident_peer(resident_id), witness, limit)
    else
      _none -> {:ok, []}
    end
  end

  def delete_conclusion(resident_id, id), do: port().delete_conclusion(resident_id, id)

  def bridge(resident_id), do: Scope.resident(resident_id, fn -> Store.bridge() end)
  def syncs(resident_id, limit), do: Scope.resident(resident_id, fn -> Store.syncs(limit) end)

  # ---- keys ----

  @doc "A workspace-scoped, expiring key for a hands runtime (spec §6.9); the key is returned once and never stored."
  def mint_key(resident_id, peer, %Actor{} = actor) do
    expires_at =
      DateTime.add(Clock.now(), Config.fetch!(:proteus, :key_ttl_hours) * 3600, :second)

    with {:ok, key} <- port().mint_key(resident_id, peer, expires_at),
         {:ok, _} <-
           dispatch(%Commands.RecordKey{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             peer: peer,
             expires_at: expires_at
           }) do
      {:ok, key, expires_at}
    else
      {:error, reason} -> {:error, failure(reason)}
    end
  end

  # ---- helpers ----

  defp port, do: Config.fetch!(:proteus, :client)

  defp hash(lines),
    do: :sha256 |> :crypto.hash(Enum.join(lines, "\n")) |> Base.encode16(case: :lower)

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, :no_such_resident}
    end
  end

  defp failure({:transport, reason}),
    do: Error.new(:proteus_honcho_unreachable, reason: reason_text(reason))

  defp failure({:rejected, reason}),
    do: Error.new(:proteus_honcho_rejected, reason: reason_text(reason))

  defp failure(%{kind: _} = error), do: error
  defp failure(:not_provisioned), do: Error.new(:proteus_not_provisioned)
  defp failure(other), do: Error.new(:proteus_honcho_rejected, reason: reason_text(other))

  defp reason_text({kind, detail}) when is_atom(kind), do: "#{kind}: #{reason_text(detail)}"
  defp reason_text(%{kind: kind}) when is_atom(kind), do: Atom.to_string(kind)
  defp reason_text(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp reason_text(text) when is_binary(text), do: text
  defp reason_text(other), do: other |> inspect() |> String.slice(0, 200)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} -> {:ok, events}
      {:error, :not_provisioned} -> {:error, Error.new(:proteus_not_provisioned)}
      {:error, reason} -> {:error, reason}
    end
  end
end
