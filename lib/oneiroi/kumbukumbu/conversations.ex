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
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Kumbukumbu.Domains
  alias Oneiroi.Kumbukumbu.Error
  alias Oneiroi.Kumbukumbu.Reacts
  alias Oneiroi.Kumbukumbu.Router
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Scope

  @doc "Opens a session of `kind` for the resident with the accounts party to it (`private: true` under a contract that keeps solo sessions private); returns its key. A `domain:` is refused: domains are per message (P23-R1, kumbukumbu#72)."
  def open_session(resident_id, kind, adapter, participants, %Actor{} = actor, opts \\ [])
      when is_list(participants) do
    key = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    private? = Keyword.get(opts, :private, false) == true

    # The imported kind is the import's alone (kumbukumbu#37): a client
    # naming it would open a session the nightly pass never reads. The
    # adapter kind is `open_adapter/5`'s alone (#40), so a session of it
    # always carries what the witness's list names it by.
    cond do
      kind in [Conversation.imported(), Conversation.adapter()] ->
        {:error,
         Error.new(:kumbukumbu_kind_invalid, :kumbukumbu_conversations_open_kind_reserved,
           kind: kind,
           kinds: Conversation.kinds()
         )}

      # A conversation has no domain (P23-R1): its messages each carry
      # one, and a session-level domain was the mistake it corrects.
      Keyword.get(opts, :domain) not in [nil, ""] ->
        {:error,
         Error.new(:kumbukumbu_domain_per_message, :kumbukumbu_conversations_open_domain_refused)}

      true ->
        # A label names what the session is for (sunna#109: a work run's
        # task and activity), shown beside its title.
        label = opts |> Keyword.get(:label) |> session_label()

        with :ok <-
               dispatch_open(
                 resident_id,
                 key,
                 kind,
                 adapter,
                 participants,
                 private?,
                 label,
                 actor
               ),
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
  Opens a session another runtime's adapter holds (kumbukumbu#40): kind
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
  What a folder is called in a conversation's name (kumbukumbu#40): the
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
  What a search from a turn in `session_key` reaches (P23-R1 §2,
  kumbukumbu#72): its conversation's current domain and the common room
  (`{:domain, current}`), or, with `across?`, her deliberate cross,
  every domain (`:any`). A key no session has is the common room.
  """
  @spec within(String.t(), String.t() | nil, boolean()) :: :any | {:domain, Domains.t()}
  def within(_resident_id, _session_key, true), do: :any

  def within(resident_id, session_key, _across?),
    do: {:domain, Domains.current(resident_id, session_key)}

  @doc """
  Whether `domain` may be named in session `key` (kumbukumbu#90): the
  common room always; any other only when the agreement declares it for
  `person`, or the conversation's counterpart when nil.
  """
  def check_domain(resident_id, key, person, domain) do
    person = whose(resident_id, key, person)
    domain = blank_nil(domain)

    # A malformed slug or person is the aggregate's to refuse, by its
    # own kind; only a well-formed one is asked whether it is declared.
    if not well_formed?(person, domain) or
         AgathosDaimon.domain_declared?(resident_id, person, domain),
       do: :ok,
       else:
         {:error,
          Error.new(:kumbukumbu_domain_undeclared, :kumbukumbu_conversations_tag_undeclared,
            domain: domain,
            declared: Enum.map(AgathosDaimon.declared_domains(resident_id), & &1.domain)
          )}
  end

  defp well_formed?(person, domain),
    do:
      is_binary(domain) and Regex.match?(~r/\A[a-z][a-z0-9-]{1,31}\z/, domain) and
        is_binary(person) and Regex.match?(~r/\A(account|resident):/, person)

  defp whose(resident_id, key, person) do
    person ||
      Scope.resident(resident_id, fn ->
        case Store.session(key) do
          nil -> nil
          session -> Domains.counterpart(session, resident_id)
        end
      end) || "resident:" <> resident_id
  end

  @doc """
  Tags a turn's messages into a domain (P23-R1, kumbukumbu#72), by its
  ref, before or after it is captured; `domain` nil is the common room.
  `person` is whose life (`"account:<id>"` or `"resident:<id>"`); nil
  takes the conversation's counterpart, the witness's in a conversation
  with him and hers in her own. Only a declared domain (kumbukumbu#90).
  """
  def tag_domain(resident_id, key, turn_ref, person, domain, %Actor{} = actor) do
    person = whose(resident_id, key, person)
    domain = blank_nil(domain)

    # Only a domain the agreement declares is named (agathos-daimon#57,
    # kumbukumbu#90): none exists without its rule.
    with :ok <- check_domain(resident_id, key, person, domain) do
      dispatch(%Commands.TagDomain{
        actor: actor,
        at: Clock.now(),
        id: stream(resident_id, key),
        resident_id: resident_id,
        session_key: key,
        turn_ref: turn_ref,
        person: person,
        domain: domain
      })
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end

  defp blank_nil(d) when is_binary(d), do: if(String.trim(d) == "", do: nil, else: String.trim(d))
  defp blank_nil(_d), do: nil

  @doc """
  The main session between a resident and its witness, opened on first
  ask (kumbukumbu#40): the platform's own conversation, the oldest of
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
  def capture(resident_id, key, turn_ref, started_at, messages, actor, opts \\ [])

  def capture(
        resident_id,
        key,
        turn_ref,
        %DateTime{} = started_at,
        messages,
        %Actor{} = actor,
        opts
      )
      when is_list(messages) do
    # Her inline reacts lifted out as a live turn of hers is kept, in any
    # runtime (kumbukumbu#56); an import's transcript is kept as it was.
    {messages, lifted} =
      if actor.kind == :resident,
        do: Reacts.lift(messages, key, turn_ref),
        else: {messages, []}

    command = %Commands.CaptureTurn{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      started_at: started_at,
      messages: Enum.map(messages, &wire_message/1),
      # The sealed letter's parties, when the turn answers one (kumbukumbu#95).
      sealed: Keyword.get(opts, :sealed)
    }

    with {:ok, _events} <- dispatch(command),
         do: Reacts.record_lifted(resident_id, lifted)
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

  @doc "Records the disclosure judge's verdict on a held-back delivery (kumbukumbu#82): a decision on the turn's stream, never the restricted words."
  def record_disclosure(resident_id, key, turn_ref, attrs, %Actor{} = actor) do
    command =
      struct(
        Commands.RecordDisclosureVerdict,
        Map.merge(attrs, %{
          actor: actor,
          at: Clock.now(),
          id: stream(resident_id, key),
          note: "the disclosure judge's verdict: #{attrs.verdict}",
          resident_id: resident_id,
          session_key: key,
          turn_ref: turn_ref
        })
      )

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  Records what retrieval did in a turn: each use `%{target, stage, via}`
  (`Events.RetrievalRecorded`). Nothing is recorded for a turn that
  retrieved nothing.
  """
  def record_retrieval(resident_id, key, turn_ref, uses, %Actor{} = actor) when is_list(uses) do
    command = %Commands.RecordRetrieval{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      ref: 12 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false),
      uses: Enum.map(uses, &Map.take(&1, [:target, :stage, :via])),
      embedding_model: ranked_with(uses)
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # A recording whose index was ranked carries its seed; it is stamped
  # with the embedding model the ranking's vectors came from (kumbukumbu
  # #46), which is the model configured now, the one the turn just read.
  defp ranked_with(uses) do
    if Enum.any?(uses, &(Map.get(&1, :stage) == "seed")),
      do: Config.fetch!(:kumbukumbu, :embedding_model),
      else: nil
  end

  @doc "Claims a submitted ref before its turn runs: `:claimed` or `:duplicate` (kumbukumbu#47)."
  def claim_turn(resident_id, key, turn_ref, stale_before, %Actor{} = actor) do
    command = %Commands.ClaimTurn{
      actor: actor,
      at: Clock.now(),
      id: stream(resident_id, key),
      resident_id: resident_id,
      session_key: key,
      turn_ref: turn_ref,
      stale_before: stale_before
    }

    case dispatch(command) do
      {:ok, [_claimed]} -> :claimed
      {:ok, []} -> :duplicate
      other -> other
    end
  end

  @doc "Each target retrieval touched, with its counts by stage, under the scope (`Store.retrieval_counts/1`)."
  def retrieval(scope, opts \\ []), do: Scope.run(scope, fn -> Store.retrieval_counts(opts) end)

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
  # the account by the projector too (kumbukumbu#28), so the policy and
  # this refusal say the same thing.
  def transcript(scope, key) do
    with {:ok, session, _} <- visible(scope, key),
         do: {:ok, session, seen(scope, Scope.run(scope, fn -> Store.messages(key) end))}
  end

  @sealed_words "[sealed: her answer to a letter between residents; its words are the letter's parties' alone (kumbukumbu#95)]"

  @doc "What a witness reads in place of a sealed turn's words (kumbukumbu#95)."
  def sealed_words, do: @sealed_words

  @doc """
  The messages as `scope` may read them (kumbukumbu#95): a witness's
  account reads a sealed turn's messages as having been said, never
  what; the resident reads her own whole.
  """
  def seen({:account, _id}, messages), do: Enum.map(messages, &witnessed/1)
  def seen(_scope, messages), do: messages

  # Her forward out of a sealed wake is her deliberate word to him
  # (kumbukumbu#98): the one line of a sealed turn he reads.
  defp witnessed(%{sealed: true, role: "tool", content: "mail_forward(" <> _} = m), do: m
  defp witnessed(%{sealed: true} = m), do: %{m | content: @sealed_words}
  defp witnessed(m), do: m

  defp seen_window({:ok, session, window}, scope),
    do: {:ok, session, %{window | messages: seen(scope, window.messages)}}

  defp seen_window(other, _scope), do: other

  @doc """
  A page of a conversation by place (kumbukumbu#94): `{:ok, session,
  messages, total}`, the messages from `offset` (0-based), at most
  `limit`, read in the database; refused as `transcript/2` refuses.
  """
  def transcript_range(scope, key, offset, limit) do
    with {:ok, session, _} <- visible(scope, key) do
      Scope.run(scope, fn ->
        {:ok, session, seen(scope, Store.messages_range(key, offset, limit)),
         Store.message_count(key)}
      end)
    end
  end

  @doc "Where a turn sits in its conversation (kumbukumbu#94): `{offset, count}` or nil."
  def turn_place(scope, key, turn_ref) do
    with {:ok, _session, _} <- visible(scope, key),
         do: Scope.run(scope, fn -> Store.turn_place(key, turn_ref) end)
  end

  @doc "A page of a session's transcript under a scope: the session, the last `limit` messages before the `{sequence, position}` cursor (nil for the newest), and whether earlier ones remain."
  def transcript_page(scope, key, before, limit) do
    with {:ok, session, _} <- visible(scope, key) do
      {messages, more} = Scope.run(scope, fn -> Store.messages_page(key, before, limit) end)
      {:ok, session, seen(scope, messages), more}
    end
  end

  @doc "A page of a session's transcript forward (kumbukumbu#57): the first `limit` messages after the cursor (nil for the oldest), and whether later ones remain."
  def transcript_after(scope, key, after_cursor, limit) do
    with {:ok, session, _} <- visible(scope, key) do
      {messages, more} =
        Scope.run(scope, fn -> Store.messages_after(key, after_cursor, limit) end)

      {:ok, session, seen(scope, messages), more}
    end
  end

  @doc """
  The window of a session's transcript around an anchor (kumbukumbu#57):
  a message's cursor (`{:cursor, {sequence, position}}`) or a turn's ref
  (`{:turn, ref}`, its first message). About half of `limit` before the
  anchor, the anchor, and the rest after it, in order, with whether
  earlier and later ones remain.
  """
  def transcript_around(scope, key, anchor, limit) do
    with {:ok, session, _} <- visible(scope, key) do
      scope |> Scope.run(fn -> around(session, key, anchor, limit) end) |> seen_window(scope)
    end
  end

  defp around(session, key, anchor, limit) do
    case Store.anchor_message(key, anchor) do
      nil ->
        {:error,
         Error.new(:kumbukumbu_no_such_message, :kumbukumbu_transcript_anchor_absent, key: key)}

      at ->
        {:ok, session, window(key, at, limit)}
    end
  end

  # About half each side; a side that runs out gives its room to the
  # other, so the window is `limit` long while the session holds that many.
  defp window(key, at, limit) do
    cursor = {at.sequence, at.position}
    {earlier, more_before} = Store.messages_page(key, cursor, div(limit, 2))
    room = max(limit - 1 - length(earlier), 0)
    {later, more_after} = Store.messages_after(key, cursor, room)

    {earlier, more_before} =
      if more_before and length(later) < room,
        do: Store.messages_page(key, cursor, max(limit - 1 - length(later), 0)),
        else: {earlier, more_before}

    %{
      messages: earlier ++ [at] ++ later,
      anchor: at,
      more_before: more_before,
      more_after: more_after
    }
  end

  # The session as `transcript/2` lets a scope see it, without its messages.
  defp visible(scope, key) do
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
          {:ok, session, nil}
      end
    end)
  end

  @doc "Every message sent in [from, to) across the resident's sessions: the nightly pass's read."
  def messages_between(resident_id, from, to),
    do: Scope.resident(resident_id, fn -> Store.messages_between(from, to) end)

  @doc "The live transcript: the last `count` messages since the session's compaction."
  def recent(resident_id, key, count),
    do: Scope.resident(resident_id, fn -> Store.recent_messages(key, count) end)

  @doc "How many turns the resident's conversations of `kind` captured since `at`."
  def turns_since(resident_id, kind, at),
    do: Scope.resident(resident_id, fn -> Store.turns_since(kind, at) end)

  @doc "The conversations with messages in `[from, to)` (kumbukumbu#73)."
  def day_sessions(resident_id, from_at, to_at),
    do: Scope.resident(resident_id, fn -> Store.day_sessions(from_at, to_at) end)

  @doc "The turns named into a domain in `[from, to)` (kumbukumbu#100)."
  def day_tag_points(resident_id, from_at, to_at),
    do: Scope.resident(resident_id, fn -> Store.day_tag_points(from_at, to_at) end)

  @doc """
  Returns to the common room every turn in `[from, to)` named into a
  domain the agreement in force does not declare (kumbukumbu#100; the
  witness, 2026-11-21: the backfill "should retag using only declared
  domains"). The tags of 11-14..16 named domains nobody declared; a tag
  carries forward until the next, so each stale point is renamed, not
  left to bleed past the new ones. `{:ok, cleared}`.
  """
  def clear_undeclared(resident_id, from_at, to_at, %Actor{} = actor) do
    stale =
      for p <- day_tag_points(resident_id, from_at, to_at),
          p.domain != nil,
          not AgathosDaimon.domain_declared?(resident_id, p.person, p.domain),
          do: p

    Enum.each(stale, fn p ->
      :ok = tag_domain(resident_id, p.session_key, p.turn_ref, p.person, nil, actor)
    end)

    {:ok, length(stale)}
  end

  @doc "How many of a session's messages came before `at`, and how many it holds in all."
  def counts(resident_id, key, at),
    do:
      Scope.resident(resident_id, fn ->
        {Store.count_before(key, at), Store.message_count(key)}
      end)

  @doc "The last `count` messages of a session whatever any compaction covered, and how many it holds in all (brain#60, truncation)."
  def latest(resident_id, key, count),
    do:
      Scope.resident(resident_id, fn ->
        {Store.latest_messages(key, count), Store.message_count(key)}
      end)

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
  The turn a tool call of `adapter` belongs to (kumbukumbu#41), and the
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
  The conversations of the resident open now (kumbukumbu#42): the main
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

  @doc "How often she called the tools named since `since`, by day and conversation kind, under a scope (kumbukumbu#71)."
  def tool_uses(scope, resident_id, names, since),
    do: Scope.run(scope, fn -> Store.tool_uses(resident_id, names, since) end)

  @doc "A session's kind, or nil when the resident holds no such session."
  def session_kind(resident_id, key) do
    Scope.resident(resident_id, fn ->
      case Store.session(key) do
        %{kind: kind} -> kind
        nil -> nil
      end
    end)
  end

  # A witness's search never matches a sealed turn (kumbukumbu#95).
  def search({:account, _} = scope, text, limit),
    do: Scope.run(scope, fn -> Store.search_unsealed(text, limit) end)

  def search(scope, text, limit), do: Scope.run(scope, fn -> Store.search(text, limit) end)

  @doc "Messages holding `text` within the current domain of `session_key` and the common room (kumbukumbu#72)."
  def search(scope, text, limit, resident_id, session_key) do
    within = within(resident_id, session_key, false)
    Scope.run(scope, fn -> Store.search(text, limit, within) end)
  end

  def failures(scope), do: Scope.run(scope, fn -> Store.open_failures() end)

  # The context inspector, as a witness reads it (kumbukumbu#95; the
  # witness, 2026-11-21: "we'll need to censor the context inspector"):
  # each section's label, tokens and reason, but no words for a turn of a
  # private session of hers or a sealed turn. Before, it answered every
  # section's text whatever the session.
  def injections({:account, _} = scope, turn_ref) do
    rows = Scope.run(scope, fn -> Store.injections(turn_ref) end)

    if censored?(scope, rows, turn_ref),
      do: Enum.map(rows, &%{&1 | text: nil}),
      else: rows
  end

  def injections(scope, turn_ref), do: Scope.run(scope, fn -> Store.injections(turn_ref) end)

  defp censored?(_scope, [], _turn_ref), do: false

  defp censored?(scope, [row | _], turn_ref) do
    not match?({:ok, _, _}, visible(scope, row.session_key)) or
      Scope.run(scope, fn -> Store.turn_sealed?(turn_ref) end)
  end

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

  defp session_label(label) when is_binary(label) do
    case label |> String.trim() |> String.slice(0, @label_chars) do
      "" -> nil
      cut -> cut
    end
  end

  defp session_label(_none), do: nil

  defp dispatch_open(resident_id, key, kind, adapter, participants, private?, label, actor) do
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
      domain: nil,
      label: label
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
      refusal: Map.get(m, :refusal, false) == true,
      # An instant the source did not carry, placed after the one before
      # it so the order holds (kumbukumbu#50): shown as unknown, never as
      # a clock reading.
      instant_inferred: Map.get(m, :instant_inferred, false) == true
    }
  end
end
