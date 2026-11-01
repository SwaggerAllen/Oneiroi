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
  alias Oneiroi.AgathosDaimon.SoulLines
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
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
    end
  end

  # ---- the card ----

  @doc """
  The card from git (spec §6.9): the soul and identity files as written,
  one line per paragraph, the soul lines' markers stripped (a number is
  for citing, not for the peer to read), each cut at #{@card_line_limit}
  characters. Never from conversation.
  """
  @spec card(String.t()) :: [String.t()]
  def card(resident_id) do
    resident_id
    |> AgathosDaimon.identity_context()
    |> Enum.filter(fn {name, _} -> name in ["SOUL.md", "IDENTITY.md"] end)
    |> Enum.flat_map(fn {_name, content} ->
      # A heading names a file, not the resident; the paragraphs are the card.
      content
      |> SoulLines.strip()
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

        with {:ok, _} <- dispatch(command), do: {:error, reason}
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
    with {:ok, before} <- last_sync(resident_id, turn_ref),
         :ok <- provisioned(resident_id, messages, actor),
         sent = Enum.flat_map(messages, &peer_message(&1, resident_id, turn_ref)),
         :ok <-
           port().ensure_session(
             resident_id,
             session_key,
             sent |> Enum.map(& &1.peer) |> Enum.uniq()
           ),
         :ok <- send_once(before, resident_id, session_key, turn_ref, sent),
         {:ok, _} <- record_sync(resident_id, session_key, turn_ref, length(sent), nil, actor) do
      :ok
    else
      :already ->
        :ok

      {:error, reason} ->
        record_sync(resident_id, session_key, turn_ref, 0, reason_text(reason), actor)
        {:error, reason}
    end
  end

  # Once per turn is the aggregate's rule, but the aggregate decides after
  # the messages are sent: the first version sent a retried turn twice
  # and recorded it once. The test that counts Honcho's messages found it.
  defp last_sync(resident_id, turn_ref) do
    case Scope.resident(resident_id, fn -> Store.sync(turn_ref) end) do
      %{outcome: "synced"} -> :already
      %{outcome: "failed"} -> {:ok, :failed}
      nil -> {:ok, :never}
    end
  end

  # A turn whose last sync failed may have landed all the same: a send
  # that timed out after Honcho committed it, or a record that failed
  # after the send. Honcho takes the same batch twice as two, so a resend
  # asks first, by the turn's ref each message carries in its metadata.
  defp send_once(:never, resident_id, session_key, _turn_ref, sent),
    do: port().add_messages(resident_id, session_key, sent)

  defp send_once(:failed, resident_id, session_key, turn_ref, sent) do
    case port().turn_sent?(resident_id, session_key, turn_ref) do
      {:ok, true} -> :ok
      {:ok, false} -> port().add_messages(resident_id, session_key, sent)
      error -> error
    end
  end

  @doc """
  Re-sends every captured turn whose last sync failed (proteus #19), in
  the order the turns were spoken, through `sync_turn/5`, so each lands
  once and is recorded as synced. Stops at the first that fails again:
  a later turn sent ahead of an earlier one would reach Honcho out of
  order. A failed row whose turn holds no captured message is left as
  it is and named, never recorded as synced with nothing sent.
  """
  def replay(resident_id, %Actor{} = actor) do
    resident_id
    |> failed_turns()
    |> Enum.reduce_while(%{synced: [], uncaptured: [], stopped: nil}, fn
      {row, []}, acc ->
        {:cont, %{acc | uncaptured: acc.uncaptured ++ [row.turn_ref]}}

      {row, messages}, acc ->
        case sync_turn(resident_id, row.session_key, row.turn_ref, messages, actor) do
          :ok ->
            {:cont, %{acc | synced: acc.synced ++ [row.turn_ref]}}

          {:error, reason} ->
            {:halt, %{acc | stopped: %{turn_ref: row.turn_ref, reason: reason_text(reason)}}}
        end
    end)
    |> then(&{:ok, &1})
  end

  # Each failed row with its turn's captured messages, as the brain
  # handed them to the sync, ordered by the turn's first message: its
  # instant, then its place in the session's stream, which orders two
  # turns of one session spoken within the same instant.
  defp failed_turns(resident_id) do
    Scope.resident(resident_id, fn -> Store.failed_syncs() end)
    |> Enum.map(&{&1, Kumbukumbu.turn_messages(resident_id, &1.turn_ref)})
    |> Enum.sort_by(fn {row, stored} -> {spoken(stored), row.turn_ref} end)
    |> Enum.map(fn {row, stored} -> {row, Enum.map(stored, &captured/1)} end)
  end

  defp spoken([]), do: {0, 0}
  defp spoken([m | _]), do: {DateTime.to_unix(m.sent_at, :microsecond), m.sequence}

  # A stored message in the shape `sync_turn/5` takes. Only the roles and
  # the actor kind the sync reads are named; the rest go as `:other`,
  # which the sync does not send, as it never sent them.
  defp captured(m) do
    %{
      role: Map.get(%{"user" => :user, "assistant" => :assistant}, m.role, :other),
      content: m.content,
      sent_at: m.sent_at,
      actor: %{kind: if(m.actor_kind == "witness", do: :witness, else: :other), id: m.actor_id}
    }
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

  defp peer_message(
         %{role: :user, actor: %{kind: :witness, id: account_id}} = m,
         _resident_id,
         turn_ref
       ),
       do: [message(witness_peer(account_id), m, turn_ref)]

  defp peer_message(%{role: :assistant} = m, resident_id, turn_ref),
    do: [message(resident_peer(resident_id), m, turn_ref)]

  defp peer_message(_other, _resident_id, _turn_ref), do: []

  defp message(peer, m, turn_ref),
    do: %{peer: peer, content: m.content, created_at: m.sent_at, turn_ref: turn_ref}

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
         {:ok, text} <- port().context(resident_id, resident_peer(resident_id), witness) do
      text |> String.trim() |> within(Config.fetch!(:proteus, :context_tokens))
    else
      _none -> ""
    end
  end

  # The bound is the bridge's to keep: Honcho's context route takes no
  # token bound (its query is the target, the search options and
  # `max_conclusions`), and the `tokens` sent before was dropped unread
  # while the brain's injection said the section was under it. Whole
  # lines while they fit, at four bytes a token as every estimate in the
  # brain is; a first line longer than the whole bound is cut inside it
  # rather than dropping the section.
  defp within(text, tokens) do
    budget = tokens * 4

    kept =
      text
      |> String.split("\n")
      |> Enum.reduce_while({[], 0}, fn line, {kept, used} ->
        cost = byte_size(line) + 1

        if used + cost > budget,
          do: {:halt, {kept, used}},
          else: {:cont, {[line | kept], used + cost}}
      end)
      |> elem(0)

    case kept do
      [] -> text |> String.graphemes() |> prefix(budget, []) |> String.trim()
      lines -> lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
    end
  end

  defp prefix([g | rest], budget, acc) when byte_size(g) <= budget,
    do: prefix(rest, budget - byte_size(g), [g | acc])

  defp prefix(_rest, _budget, acc), do: acc |> Enum.reverse() |> Enum.join()

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

  @doc """
  Everything Honcho holds about the resident's workspace that is text
  only Honcho holds (proteus #18), for the records export: every peer;
  every card each peer holds, of itself and of each other peer; every
  conclusion; and every session's summaries. `{:ok, nil}` before the
  bridge is provisioned, when there is no workspace to read. One failed
  read fails the whole, so a part is never taken for the whole.
  `port` is the setting's in every caller but the HTTP boundary's test.
  """
  @spec memory(String.t(), module()) :: {:ok, map() | nil} | {:error, term()}
  def memory(resident_id, port \\ port()) do
    case bridge(resident_id) do
      nil -> {:ok, nil}
      %{workspace: ws} -> read_memory(port, ws)
    end
  end

  defp read_memory(port, ws) do
    with {:ok, peers} <- port.peers(ws),
         {:ok, cards} <- cards(port, ws, peers),
         {:ok, conclusions} <- port.all_conclusions(ws),
         {:ok, sessions} <- port.sessions(ws),
         {:ok, summaries} <- summaries(port, ws, sessions) do
      {:ok, %{peers: peers, cards: cards, conclusions: conclusions, summaries: summaries}}
    end
  end

  # Each peer's card of itself and of every other peer, where it holds one.
  defp cards(port, ws, peers) do
    pairs = for observer <- peers, target <- peers, do: {observer, target}

    Enum.reduce_while(pairs, {:ok, []}, fn {observer, target}, {:ok, acc} ->
      case port.peer_card(ws, observer, target) do
        {:ok, lines} when is_list(lines) and lines != [] ->
          {:cont, {:ok, acc ++ [%{observer: observer, target: target, lines: lines}]}}

        {:ok, _none} ->
          {:cont, {:ok, acc}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp summaries(port, ws, sessions) do
    Enum.reduce_while(sessions, {:ok, []}, fn session, {:ok, acc} ->
      case port.summaries(ws, session) do
        {:ok, %{short: nil, long: nil}} -> {:cont, {:ok, acc}}
        {:ok, both} -> {:cont, {:ok, acc ++ [Map.put(both, :session, session)]}}
        error -> {:halt, error}
      end
    end)
  end

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
    end
  end

  # ---- helpers ----

  defp port, do: Config.fetch!(:proteus, :client)

  defp hash(lines),
    do: :sha256 |> :crypto.hash(Enum.join(lines, "\n")) |> Base.encode16(case: :lower)

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        {:ok, row}

      :error ->
        {:error,
         Error.new(:proteus_no_such_resident, :proteus_bridges_resident_absent,
           resident_id: resident_id
         )}
    end
  end

  # What the bridge records of a failure on the resident's stream:
  # Honcho's side as `transport: <cause>` or `rejected: <status>`, ours
  # by kind. Never a body or a message, which can carry a tenant's words.
  defp reason_text(%{kind: :proteus_honcho_unreachable} = e), do: "transport: " <> cause_text(e)

  defp reason_text(%{kind: :proteus_honcho_rejected} = e),
    do: "rejected: " <> to_string(Keyword.get(e.details, :status) || cause_text(e))

  defp reason_text(%{kind: kind}), do: Atom.to_string(kind)

  # The cause's class, or the line that built the error when it wraps nothing.
  defp cause_text(%{cause: nil, site: site}), do: Atom.to_string(site)

  defp cause_text(%{cause: cause}),
    do: cause |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

  # The aggregate's refusals arrive sited (`Bridge`); what else a
  # dispatch answers, the actor middleware's refusal or the store's own
  # failure, is wrapped here, once, where it is first matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, {:refused, problems} = refusal} ->
        {:error,
         Error.caught(:proteus_command_refused, :proteus_bridges_command_refused, refusal,
           problems: problems
         )}

      {:error, reason} ->
        {:error,
         Error.caught(:proteus_dispatch_failed, :proteus_bridges_dispatch_failed, reason,
           command: command.__struct__
         )}
    end
  end
end
