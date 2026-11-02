defmodule OneiroiWeb.ConversationController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Kumbukumbu
  alias OpenApiSpex.Schema

  tags(["memory"])

  plug(:witnessed)

  # The adapter contract's routes (spec §8): an adapter with the brain
  # role, speaking for this resident, may open its session, start and
  # capture turns and read the context; a witness may do all of it.
  @adapter_actions ~w(create turn_start capture context)a

  operation(:index,
    summary:
      "The resident's sessions this account was party to, last spoken in first, each with what it is called and whether you can write in it",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"sessions", "application/json", %Schema{type: :array}}]
  )

  # Ordered by when each was last spoken in, not opened: a Claude Code
  # conversation opened in the morning and worked in all day is the
  # newest, and the client groups by `title` in this order (kumbukumbu
  # #40).
  def index(%{assigns: %{principal: p}} = conn, %{"id" => id}) do
    rows =
      {:account, p.account_id}
      |> Kumbukumbu.sessions()
      |> Enum.filter(&(&1.resident_id == id))
      |> Enum.sort_by(
        &DateTime.to_unix(Kumbukumbu.Conversations.last_at(&1), :microsecond),
        :desc
      )

    json(conn, Enum.map(rows, &session/1))
  end

  operation(:create,
    summary:
      "Open a session, or return the main one between this account and the resident; an adapter's token always opens a new conversation of its own",
    description:
      "For a witness, `main` is the Oneiroi chat, opened once and found again. For an adapter's token the kind sent is not read: every session it opens is a new one of kind `adapter` (kumbukumbu #40), called by `label`, of which only the folder's base name is kept, and `runtime`. A plugin built before the kind existed sends `main` and still lands as an adapter's conversation.",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the kind", "application/json",
       %Schema{
         type: :object,
         properties: %{
           kind: %Schema{type: :string, enum: ["main", "free_time", "hands"]},
           domain: %Schema{
             type: :string,
             description:
               "the room (spec §6.3, P23): a slug such as intimate, business or family; absent for the common room"
           },
           label: %Schema{
             type: :string,
             description:
               "an adapter's: the folder the runtime runs in, of which the server keeps the base name alone"
           },
           runtime: %Schema{
             type: :string,
             description: "an adapter's: the runtime, such as claude-code"
           }
         }
       }},
    responses: [created: {"the session key", "application/json", %Schema{type: :object}}]
  )

  def create(conn, %{"id" => id} = params) do
    {party, adapter_name} = party_of(conn, id)

    result =
      case {Map.get(params, "kind", "main"), adapter(conn)} do
        # The principal decides, never the body: the Oneiroi chat is the
        # canonical conversation and an adapter's is secondary to it
        # (kumbukumbu #40), and the plugin keeps sending `main` so it
        # still works against a server from before the kind.
        {_kind, %{}} ->
          Kumbukumbu.open_adapter(id, adapter_name, [party], actor(conn),
            label: params["label"],
            runtime: params["runtime"]
          )

        {"main", nil} ->
          Kumbukumbu.main_session(id, party, actor(conn))

        {kind, nil} ->
          Kumbukumbu.open_session(id, kind, adapter_name, [party], actor(conn),
            domain: Map.get(params, "domain")
          )
      end

    case result do
      {:ok, key} ->
        conn |> put_status(201) |> json(%{key: key})

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  operation(:show,
    summary: "A session's transcript",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    responses: [ok: {"the session and its messages", "application/json", %Schema{type: :object}}]
  )

  def show(%{assigns: %{principal: p}} = conn, %{"key" => key}) do
    case Kumbukumbu.transcript({:account, p.account_id}, key) do
      {:ok, s, messages} ->
        json(conn, %{
          session: session(s),
          messages: Enum.map(messages, &message/1),
          # Each turn's count for "drew on N things", so a reply read
          # later, or in a conversation the witness did not send in,
          # opens the same inspector a reply just sent does.
          drew_on: Kumbukumbu.drew_on({:account, p.account_id}, key)
        })

      {:error, %Kumbukumbu.Error{} = e} ->
        error(conn, 404, e)
    end
  end

  operation(:turn,
    summary: "Send a message and wait for the turn: the reply streams on the channel too",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"the message", "application/json",
       %Schema{type: :object, required: [:text], properties: %{text: %Schema{type: :string}}}},
    responses: [created: {"the captured turn", "application/json", %Schema{type: :object}}]
  )

  def turn(%{assigns: %{principal: p}} = conn, %{"id" => id, "key" => key, "text" => text})
      when is_binary(text) do
    case read_only(p, key) do
      nil -> run_turn(conn, id, key, text)
      s -> read_only_problem(conn, s)
    end
  end

  def turn(conn, _params),
    do:
      problem(conn, 422, :text_required, :web_conversation_turn_text_required, "text is required")

  # A conversation the witness replies in elsewhere (kumbukumbu #40): the
  # platform's brain answering in it would put the Oneiroi chat's turn in
  # a Claude Code conversation, the confusion the kind exists to end.
  defp read_only(%{account_id: account_id}, key) do
    case Kumbukumbu.transcript({:account, account_id}, key) do
      {:ok, s, _messages} -> if Kumbukumbu.Conversation.writable?(s.kind), do: nil, else: s
      {:error, _e} -> nil
    end
  end

  defp read_only(_principal, _key), do: nil

  defp read_only_problem(conn, s),
    do:
      problem(
        conn,
        409,
        :read_only,
        :web_conversation_turn_read_only,
        "#{title(s)} is read here: it is answered where it happens"
      )

  defp run_turn(conn, id, key, text) do
    case Oneiroi.Brain.turn(id, key, text, actor(conn)) do
      {:ok, turn} ->
        conn |> put_status(201) |> json(turn)

      {:error, %{kind: :brain_budget_stopped, details: details}} ->
        conn
        |> put_status(402)
        |> json(Map.put(details[:turn], :stopped, stop_body(details[:stop])))

      {:error, %{kind: :brain_no_such_resident} = e} ->
        error(conn, 422, e)

      {:error, e} ->
        error(conn, 502, e)
    end
  end

  operation(:search,
    summary: "Messages holding the text, newest first, unweighted",
    parameters: [id: [in: :path, type: :string], q: [in: :query, type: :string]],
    responses: [ok: {"messages", "application/json", %Schema{type: :array}}]
  )

  def search(%{assigns: %{principal: p}} = conn, %{"id" => id, "q" => q}) when is_binary(q) do
    rows =
      {:account, p.account_id}
      |> Kumbukumbu.search(q, 100)
      |> Enum.filter(&(&1.resident_id == id))

    json(conn, Enum.map(rows, &message/1))
  end

  def search(conn, _params),
    do:
      problem(
        conn,
        422,
        :query_required,
        :web_conversation_search_query_required,
        "q is required"
      )

  operation(:failures,
    summary: "The open capture failures, oldest first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"failures", "application/json", %Schema{type: :array}}]
  )

  def failures(%{assigns: %{principal: p}} = conn, %{"id" => id}) do
    rows =
      {:account, p.account_id} |> Kumbukumbu.failures() |> Enum.filter(&(&1.resident_id == id))

    json(conn, Enum.map(rows, &failure/1))
  end

  operation(:resolve,
    summary: "Resolve a capture failure: retried or marked lost, with a note",
    parameters: [id: [in: :path, type: :string], turn_ref: [in: :path, type: :string]],
    request_body:
      {"how and why", "application/json",
       %Schema{
         type: :object,
         required: [:key, :how, :note],
         properties: %{
           key: %Schema{type: :string},
           how: %Schema{type: :string, enum: ["retried", "marked_lost"]},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "resolved"]
  )

  def resolve(conn, %{
        "id" => id,
        "turn_ref" => turn_ref,
        "key" => key,
        "how" => how,
        "note" => note
      }) do
    case Kumbukumbu.resolve_failure(id, key, turn_ref, how, note, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, %{kind: :kumbukumbu_no_such_failure} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def resolve(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_conversation_resolve_fields_required,
        "key, how and note are required"
      )

  operation(:injections,
    summary: "What a turn drew on: the 'drew on N things' inspector",
    parameters: [id: [in: :path, type: :string], turn_ref: [in: :path, type: :string]],
    responses: [ok: {"injections", "application/json", %Schema{type: :array}}]
  )

  def injections(%{assigns: %{principal: p}} = conn, %{"turn_ref" => turn_ref}) do
    rows = Kumbukumbu.injections({:account, p.account_id}, turn_ref)

    json(
      conn,
      Enum.map(
        rows,
        &%{
          label: &1.label,
          tokens: &1.tokens,
          reason: &1.reason,
          position: &1.position,
          text: &1.text
        }
      )
    )
  end

  operation(:preview,
    summary:
      "What the resident will see next in this session (brain #41): the next turn's assembly as a dry run, every section in order with its tokens and reason, its words only where you read them elsewhere; nothing recorded",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"the draft so far", "application/json",
       %Schema{type: :object, properties: %{text: %Schema{type: :string}}}},
    responses: [ok: {"the preview", "application/json", %Schema{type: :object}}]
  )

  # A POST that writes nothing: the draft rides the body, never the URL,
  # since a query string is what an access log keeps. Witness-only: an
  # adapter's token is not in `@adapter_actions` here, and the session
  # must be one this account reads, so a private session or another
  # account's is a 404 as its transcript is.
  def preview(%{assigns: %{principal: p}} = conn, %{"id" => id, "key" => key} = params) do
    text = if is_binary(params["text"]), do: params["text"], else: ""

    with {:ok, %{resident_id: ^id}, _messages} <-
           Kumbukumbu.transcript({:account, p.account_id}, key),
         {:ok, preview} <- Oneiroi.Brain.preview(id, key, text, actor(conn)) do
      json(conn, preview)
    else
      {:ok, _elsewhere, _messages} ->
        problem(
          conn,
          404,
          :no_such_session,
          :web_conversation_preview_session_elsewhere,
          "no session with that key is this resident's"
        )

      {:error, %Kumbukumbu.Error{} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  operation(:capture,
    summary:
      "An adapter captures a turn (spec §8): idempotent on the session, the start instant and the content",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the turn", "application/json",
       %Schema{
         type: :object,
         required: [:session_key, :started_at, :messages],
         properties: %{
           session_key: %Schema{type: :string},
           turn_ref: %Schema{type: :string},
           started_at: %Schema{type: :string, format: :"date-time"},
           messages: %Schema{type: :array, items: %Schema{type: :object}}
         }
       }},
    responses: [created: {"the turn ref", "application/json", %Schema{type: :object}}]
  )

  def capture(
        conn,
        %{"id" => id, "session_key" => key, "started_at" => started, "messages" => messages} =
          params
      )
      when is_list(messages) do
    turn_ref = Map.get(params, "turn_ref") || Kumbukumbu.turn_ref()

    with {:ok, started_at} <- parse_started(started),
         {:ok, built} <- build_messages(messages, actor(conn)),
         :ok <- Kumbukumbu.capture(id, key, turn_ref, started_at, built, actor(conn)) do
      conn |> put_status(201) |> json(%{turn_ref: turn_ref})
    else
      :started_at_invalid ->
        problem(
          conn,
          422,
          :started_at_invalid,
          :web_conversation_capture_started_at_invalid,
          "started_at is an ISO 8601 instant with its offset"
        )

      :message_invalid ->
        problem(
          conn,
          422,
          :message_invalid,
          :web_conversation_capture_message_invalid,
          "each message needs a role and content"
        )

      {:error, %{kind: kind} = e}
      when kind in [:kumbukumbu_no_such_session, :kumbukumbu_empty_turn] ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def capture(conn, _params),
    do:
      problem(
        conn,
        422,
        :fields_required,
        :web_conversation_capture_fields_required,
        "session_key, started_at and messages are required"
      )

  # The request's own fields, checked at the edge: a bare atom names the
  # problem/5 the capture answers with, and no component sees it.
  defp parse_started(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, _reason} -> :started_at_invalid
    end
  end

  defp parse_started(_other), do: :started_at_invalid

  operation(:turn_start,
    summary:
      "A turn begins (spec §8): the ref to capture it under and, for the resident's brain adapter, the turn's context assembled against the witness's words",
    description:
      "For an adapter's token the turn is assembled as a platform turn is (brain #42), against `text` in the session's room: the index and every section after the prefix, the once-only notices the runtime can be told, and any part of the prefix whose hash moved since `prefix_digest`; what is handed over is recorded as the turn's ContextAssembled. `limit` is how many characters the runtime takes at once: sections past it are left out whole and named. For a witness's token the turn is started and nothing is assembled.",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the session and the witness's words", "application/json",
       %Schema{
         type: :object,
         required: [:session_key],
         properties: %{
           session_key: %Schema{type: :string},
           text: %Schema{type: :string, description: "the witness's words opening the turn"},
           prefix_digest: %Schema{
             type: :string,
             description:
               "the digest of the prefix the runtime's session holds, as GET context gave it"
           },
           runtime: %Schema{type: :string, enum: ["claude-code"]},
           limit: %Schema{type: :integer, description: "the characters the runtime takes at once"}
         }
       }},
    responses: [
      created: {"the turn ref, and the context", "application/json", %Schema{type: :object}}
    ]
  )

  def turn_start(conn, %{"id" => id, "session_key" => key} = params) do
    result =
      case adapter(conn) do
        nil -> start_bare(id, key, actor(conn))
        _adapter -> Oneiroi.Brain.adapter_turn(id, key, text(params), actor(conn), opts(params))
      end

    case result do
      {:ok, turn} ->
        conn |> put_status(201) |> json(turn)

      {:error, %{kind: :kumbukumbu_no_such_session} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def turn_start(conn, _params),
    do:
      problem(
        conn,
        422,
        :session_key_required,
        :web_conversation_turn_start_session_key_required,
        "session_key is required"
      )

  # A witness's turn-start gives nobody a context, so it assembles and
  # records none: the turn is started and its ref returned.
  defp start_bare(id, key, actor) do
    turn_ref = Kumbukumbu.turn_ref()

    with :ok <- Kumbukumbu.start_turn(id, key, turn_ref, actor),
         do: {:ok, %{turn_ref: turn_ref}}
  end

  defp text(%{"text" => text}) when is_binary(text), do: text
  defp text(_params), do: ""

  defp opts(params),
    do: [
      runtime: params["runtime"],
      limit: integer(params["limit"]),
      digest: params["prefix_digest"]
    ]

  operation(:context,
    summary:
      "The session prefix for the resident's brain adapter (spec §8, brain #42): the prompt, the identity files and the contract, as text in parts the runtime can print; records nothing",
    description:
      "What is the same for every turn of a session, by the function the platform's own turn assembles its prefix with. `limit` cuts it into parts at paragraph boundaries, `of` is how many the runtime prints and `part` which one this is; past `of` parts the rest is left out and the last part says how much. `digest` is what the runtime sends back with each turn so a changed section rides that turn. The per-turn part (the index and after) is the turn-start's answer. An adapter's token only: a witness reads the next turn's context through the preview.",
    parameters: [
      id: [in: :path, type: :string],
      runtime: [in: :query, type: :string],
      limit: [in: :query, type: :integer],
      part: [in: :query, type: :integer],
      of: [in: :query, type: :integer]
    ],
    responses: [ok: {"the prefix part", "application/json", %Schema{type: :object}}]
  )

  # The prefix carries the platform's prompt, which a witness under the
  # preview term reads nowhere (brain #41); the witness's route to what a
  # turn is given is the preview, so this one is the runtime's alone.
  def context(conn, %{"id" => id} = params) do
    opts = [
      runtime: params["runtime"],
      limit: integer(params["limit"]),
      part: integer(params["part"]),
      of: integer(params["of"])
    ]

    with %{} <- adapter(conn),
         {:ok, prefix} <- Oneiroi.Brain.adapter_prefix(id, opts) do
      json(conn, prefix)
    else
      nil ->
        problem(
          conn,
          404,
          :adapter_only,
          :web_conversation_context_adapter_only,
          "the context is the resident's runtime's to read; yours is the preview of a session"
        )

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp integer(_other), do: nil

  # Every route here is a resident's, read or written by its witness, or
  # by its brain-role adapter on the adapter contract's routes.
  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    allowed? =
      case conn.assigns.principal do
        %{account_id: account_id} ->
          id in Oneiroi.Gaia.witnessed_residents(account_id)

        %{resident_id: ^id, role: "brain"} ->
          Phoenix.Controller.action_name(conn) in @adapter_actions

        _other ->
          false
      end

    if allowed?,
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_conversation_not_witnessed
          )
        )
        |> halt()
  end

  # The account party to a session an adapter opens is the resident's
  # witness (spec §6.3: solo sessions are the witness's to read).
  defp party_of(conn, id) do
    case {conn.assigns.principal, Oneiroi.AgathosDaimon.fetch(id)} do
      {%{account_id: account_id}, _} -> {account_id, "brain"}
      {%{adapter: name}, {:ok, %{account_id: account_id}}} -> {account_id, name}
      {%{adapter: name}, :error} -> {nil, name}
    end
  end

  # A closed map rather than `String.to_existing_atom/1`: the atom is
  # created by the code that names it, and an adapter's capture once ran
  # in a process where nothing had loaded that code yet.
  @roles %{"user" => :user, "assistant" => :assistant, "system" => :system, "tool" => :tool}

  defp build_messages(messages, actor) do
    built =
      Enum.map(messages, fn
        %{"role" => role, "content" => content} = m
        when is_map_key(@roles, role) and is_binary(content) ->
          %{
            role: Map.fetch!(@roles, role),
            content: content,
            sent_at: parse_instant(m["sent_at"]),
            actor: message_actor(role, actor),
            refusal: m["refusal"] == true
          }

        _other ->
          :invalid
      end)

    if :invalid in built, do: :message_invalid, else: {:ok, built}
  end

  # An adapter captures as the resident; the user messages in its turn are
  # the witness's words, so they carry the witness's kind.
  defp message_actor("user", %{kind: :resident}), do: Oneiroi.Actor.new(:witness)
  defp message_actor(_role, actor), do: actor

  defp parse_instant(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp parse_instant(_), do: nil

  defp stop_body(stop),
    do: %{kind: Atom.to_string(stop.kind), meaning: stop.meaning, remedy: stop.remedy}

  # What each conversation is called and whether the witness writes in
  # it, decided here so the client holds none of the rule (kumbukumbu
  # #40): `title` names it and is what the client groups by, `place` is
  # the folder an adapter's ran in, `writable` says whether it takes a
  # message.
  defp session(s) do
    %{
      key: s.key,
      resident_id: s.resident_id,
      kind: s.kind,
      adapter: s.adapter,
      runtime: s.runtime,
      label: s.label,
      title: title(s),
      place: s.label,
      writable: Kumbukumbu.Conversation.writable?(s.kind),
      participants: s.participants,
      domain: s.domain,
      shared: s.shared,
      opened_at: s.opened_at,
      last_turn_at: s.last_turn_at,
      turns: s.turns,
      summary: s.summary,
      compacted_through: s.compacted_through
    }
  end

  defp title(%{kind: "main"}), do: "Oneiroi chat"
  defp title(%{kind: "free_time"}), do: "Free time"
  defp title(%{kind: "hands"}), do: "Hands"
  defp title(%{kind: "imported", adapter: adapter}), do: "Imported from #{adapter}"

  defp title(%{kind: "adapter"} = s) do
    runtime = Kumbukumbu.Conversation.runtime_name(s.runtime, s.adapter)
    if s.label, do: "#{runtime} · #{s.label}", else: runtime
  end

  defp title(%{kind: kind}), do: kind

  defp message(m) do
    %{
      session_key: m.session_key,
      turn_ref: m.turn_ref,
      role: m.role,
      content: m.content,
      sent_at: m.sent_at,
      actor: %{kind: m.actor_kind, id: m.actor_id, model: m.model},
      refusal: m.refusal
    }
  end

  defp failure(f),
    do: %{
      turn_ref: f.turn_ref,
      session_key: f.session_key,
      reason: f.reason,
      failed_at: f.failed_at
    }
end
