defmodule Oneiroi.Kumbukumbu.Conversations do
  @moduledoc """
  Memory's service functions for conversations: the command edge, where
  session keys, turn refs, instants and content hashes are made, and the
  reads the transcript screen and the brain take.

  Reads for a witness run under the account's scope, which is the
  visibility rule itself (spec §6.3): an account sees the sessions it
  was party to and nothing else, enforced by the policy on the rows.
  The brain reads under the resident's scope and sees everything.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Router
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @doc "Opens a session of `kind` for the resident with the accounts party to it (`private: true` under a contract that keeps solo sessions private; `domain:` the room, spec §6.3 P23); returns its key."
  def open_session(resident_id, kind, adapter, participants, %Actor{} = actor, opts \\ [])
      when is_list(participants) do
    key = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    private? = Keyword.get(opts, :private, false) == true
    domain = Keyword.get(opts, :domain)

    # The imported kind is the import's alone (kumbukumbu #37): a client
    # naming it would open a session the nightly pass never reads. The
    # adapter kind is `open_adapter/5`'s alone (#40), so a session of it
    # always carries what the witness's list names it by.
    if kind in [Conversation.imported(), Conversation.adapter()] do
      {:error,
       Error.new(:kumbukumbu_kind_invalid, :kumbukumbu_conversations_open_kind_reserved,
         kind: kind,
         kinds: Conversation.kinds()
       )}
    else
      with :ok <-
             dispatch_open(resident_id, key, kind, adapter, participants, private?, domain, actor),
           do: {:ok, key}
    end
  end

  @doc """
  Opens a session carried from another platform by an import (kumbukumbu
  #37): kind `imported`, in the common room, with `adapter` naming the
  platform it came from. Its turns are captured with `capture/6` as any
  other's, their instants the originals; returns its key.
  """
  def open_imported(resident_id, adapter, participants, %Actor{} = actor)
      when is_binary(adapter) and is_list(participants) do
    key = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    kind = Conversation.imported()

    with :ok <- dispatch_open(resident_id, key, kind, adapter, participants, false, nil, actor),
         do: {:ok, key}
  end

  @doc """
  Opens a session another runtime's adapter holds (kumbukumbu #40): kind
  `adapter`, in the common room, with the witness as its party, called
  by `label` (the folder the runtime ran in, by its base name alone,
  `folder_label/1`) and `runtime` (a slug such as `claude-code`, or nil).
  Each call opens a new one: a runtime's conversation is its own, and
  never the platform's main session with the witness. Returns its key.
  """
  def open_adapter(resident_id, adapter, participants, %Actor{} = actor, opts \\ [])
      when is_binary(adapter) and is_list(participants) do
    key = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    command = %Commands.OpenSession{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      kind: Conversation.adapter(),
      adapter: adapter,
      participants: participants,
      private: false,
      domain: nil,
      label: opts |> Keyword.get(:label) |> folder_label(),
      runtime: opts |> Keyword.get(:runtime) |> runtime()
    }

    with {:ok, _} <- dispatch(command), do: {:ok, key}
  end

  @label_chars 64
  @runtime ~r/\A[a-z][a-z0-9-]{1,31}\z/

  @doc """
  What a folder is called in a conversation's name (kumbukumbu #40): the
  last segment of whatever path is given, either separator, trimmed and
  cut at #{@label_chars} characters, or nil when nothing is left. A
  folder's full path names the witness's machine, the account on it and
  everything above the project, and none of that is the resident's to
  hold or the witness's list's to show, so the server keeps the base
  name even when an adapter sends more.
  """
  @spec folder_label(term()) :: String.t() | nil
  def folder_label(path) when is_binary(path) do
    label =
      path
      |> String.split(["/", "\\"], trim: true)
      |> List.last("")
      |> String.replace(~r/[[:cntrl:]]/u, "")
      |> String.trim()
      |> String.slice(0, @label_chars)

    if label in ["", ".", ".."], do: nil, else: label
  end

  def folder_label(_other), do: nil

  defp runtime(name) when is_binary(name),
    do: if(Regex.match?(@runtime, name), do: name, else: nil)

  defp runtime(_other), do: nil

  @doc """
  The room a session is in (spec §6.3, P23): its domain, nil for the
  common room, and the keys of every session whose material may be
  retrieved from it: the sessions of the same domain and the common
  room's. The common room sees the common room alone, so a domain's
  material never reaches a session that did not name it. A key no
  session has is the common room.
  """
  def room(resident_id, session_key) do
    Scope.resident(resident_id, fn ->
      sessions = Store.sessions()
      domain = Enum.find_value(sessions, fn s -> s.key == session_key && s.domain end)

      keys =
        sessions
        |> Enum.filter(&(is_nil(&1.domain) or &1.domain == domain))
        |> Enum.map(& &1.key)

      %{domain: domain, keys: keys}
    end)
  end

  @doc """
  The main session between a resident and its witness, opened on first
  ask (kumbukumbu #40): the platform's own conversation, the oldest of
  kind `main` by its opening and then its key, so the answer never turns
  on the order rows come back in. Kind `main` is the platform adapter's
  alone, by `Conversation.kind_for/2` at the open and in the upcaster,
  so a session another runtime opened is never it; a filter on the
  adapter here as well was probed and found inert, and is not kept.
  """
  def main_session(resident_id, account_id, %Actor{} = actor) do
    existing =
      Scope.account(account_id, fn ->
        Store.sessions()
        |> Enum.filter(&(&1.resident_id == resident_id and &1.kind == "main"))
        |> Enum.min_by(&{DateTime.to_unix(&1.opened_at, :microsecond), &1.key}, fn -> nil end)
      end)

    case existing do
      %{key: key} -> {:ok, key}
      nil -> open_session(resident_id, "main", Conversation.platform(), [account_id], actor)
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

    with {:ok, _} <- dispatch(command), do: :ok
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

    with {:ok, _events} <- dispatch(command), do: :ok
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

    with {:ok, _} <- dispatch(command), do: :ok
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

    with {:ok, _} <- dispatch(command), do: :ok
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

    with {:ok, _} <- dispatch(command), do: :ok
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

    with {:ok, _} <- dispatch(command), do: :ok
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

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- reads ----

  @doc "The sessions a scope sees: `{:account, id}` for a witness, `{:resident, id}` for the brain."
  def sessions(scope), do: Scope.run(scope, fn -> Store.sessions() end)

  # A private, unshared session is a locked row to the account party:
  # listed, never opened (spec §6.3). The messages are keyed away from
  # the account by the projector too (kumbukumbu #28), so the policy and
  # this refusal say the same thing.
  def transcript(scope, key) do
    Scope.run(scope, fn ->
      case {scope, Store.session(key)} do
        {_scope, nil} ->
          {:error,
           Error.new(:kumbukumbu_no_such_session, :kumbukumbu_transcript_session_absent, key: key)}

        {{:account, _}, %{private: true, shared: false}} ->
          {:error,
           Error.new(:kumbukumbu_session_private, :kumbukumbu_transcript_session_private,
             key: key
           )}

        {_scope, session} ->
          {:ok, session, Store.messages(key)}
      end
    end)
  end

  @doc "Every message sent in [from, to) across the resident's sessions: the nightly pass's read."
  def messages_between(resident_id, from, to),
    do: Scope.resident(resident_id, fn -> Store.messages_between(from, to) end)

  @doc "The live transcript: the last `count` messages since the session's compaction."
  def recent(resident_id, key, count),
    do: Scope.resident(resident_id, fn -> Store.recent_messages(key, count) end)

  @doc "The session and what compaction has not covered: the count of messages after it, and those messages."
  def uncompacted(resident_id, key) do
    Scope.resident(resident_id, fn ->
      case Store.session(key) do
        nil ->
          {:error,
           Error.new(:kumbukumbu_no_such_session, :kumbukumbu_uncompacted_session_absent,
             key: key
           )}

        s ->
          count = Store.messages_after(key, s.compacted_through)
          {:ok, s, count}
      end
    end)
  end

  @doc "The adapter's open turn: `{session_key, turn_ref}` of its latest started, uncaptured turn, or nil."
  def open_turn(resident_id, adapter) do
    Scope.resident(resident_id, fn ->
      case Store.open_turn(adapter) do
        nil -> nil
        s -> {s.key, s.open_turn_ref}
      end
    end)
  end

  @doc """
  The turn a tool call of `adapter` belongs to (kumbukumbu #41), and the
  rule that chose it. The runtime's model is told each turn's ref and
  passes it back as `turn`: a named ref that is an open turn of this
  adapter's, for this resident, is that turn (`:named`). Anything else,
  no ref, a captured turn's, another adapter's or a made-up one, falls
  back to the newest open turn of the adapter (`:newest`), which is the
  only rule there was before two conversations could be open at once;
  with no open turn at all, none (`:none`). `open` is how many turns of
  the adapter's were open, so a caller can tell a fallback that had one
  answer from one that chose among several. Each attribution is a
  `[:oneiroi, :kumbukumbu, :turn_attributed]` event with its rule.
  """
  @spec attribute(String.t(), String.t(), String.t() | nil) :: %{
          session_key: String.t() | nil,
          turn_ref: String.t() | nil,
          label: String.t() | nil,
          rule: :named | :newest | :none,
          open: non_neg_integer()
        }
  def attribute(resident_id, adapter, named) do
    open = Scope.resident(resident_id, fn -> Store.open_turns(adapter) end)

    attribution =
      case {Enum.find(open, &(is_binary(named) and &1.open_turn_ref == named)), open} do
        {%{} = s, _open} -> attributed(s, :named, length(open))
        {nil, [newest | _]} -> attributed(newest, :newest, length(open))
        {nil, []} -> %{session_key: nil, turn_ref: nil, label: nil, rule: :none, open: 0}
      end

    :telemetry.execute([:oneiroi, :kumbukumbu, :turn_attributed], %{count: 1}, %{
      rule: attribution.rule,
      open: attribution.open
    })

    attribution
  end

  defp attributed(s, rule, open),
    do: %{session_key: s.key, turn_ref: s.open_turn_ref, label: s.label, rule: rule, open: open}

  @doc """
  The conversations of the resident open now (kumbukumbu #42): the main
  session and every adapter's, each with a turn in flight or a turn or
  an opening within `KUMBUKUMBU_OPEN_MINUTES`, newest first. A
  conversation has no close in this protocol (a runtime that quits says
  nothing), so "open" is "spoken in lately", and says so where it is
  shown.
  """
  def open_now(resident_id) do
    since = DateTime.add(Clock.now(), -Config.fetch!(:kumbukumbu, :open_minutes) * 60, :second)
    kinds = ["main", Conversation.adapter()]

    Scope.resident(resident_id, fn ->
      kinds
      |> Store.open_since(since)
      |> Enum.sort_by(&{DateTime.to_unix(last_at(&1), :microsecond), &1.key}, :desc)
      |> Enum.map(fn s ->
        %{
          key: s.key,
          kind: s.kind,
          adapter: s.adapter,
          runtime: s.runtime,
          label: s.label,
          last_at: last_at(s),
          in_flight: not is_nil(s.open_turn_ref)
        }
      end)
    end)
  end

  @doc "When a session was last spoken in: its open turn's start, else its last captured turn, else its opening."
  @spec last_at(Store.Session.t()) :: DateTime.t()
  def last_at(s), do: s.open_turn_at || s.last_turn_at || s.opened_at

  @doc "How many things each turn of a session drew on, by turn ref, under a scope: the inspector's counts."
  def drew_on(scope, key), do: Scope.run(scope, fn -> Store.drew_on(key) end)

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

  @doc "Messages holding `text` within the room of `session_key` (spec §6.3, P23): the sessions of its domain and the common room's."
  def search(scope, text, limit, resident_id, session_key) do
    %{keys: keys} = room(resident_id, session_key)
    Scope.run(scope, fn -> Store.search(text, limit, keys) end)
  end

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

  defp dispatch_open(resident_id, key, kind, adapter, participants, private?, domain, actor) do
    command = %Commands.OpenSession{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      kind: kind,
      adapter: adapter,
      participants: participants,
      private: private?,
      domain: domain
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # The aggregate's refusals arrive sited (`Conversation`); what else a
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
         Error.caught(
           :kumbukumbu_command_refused,
           :kumbukumbu_conversations_command_refused,
           refusal,
           problems: problems
         )}

      {:error, reason} ->
        {:error,
         Error.caught(
           :kumbukumbu_dispatch_failed,
           :kumbukumbu_conversations_dispatch_failed,
           reason,
           command: command.__struct__
         )}
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
