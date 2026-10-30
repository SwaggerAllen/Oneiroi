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
    summary: "The resident's sessions this account was party to, newest first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"sessions", "application/json", %Schema{type: :array}}]
  )

  def index(%{assigns: %{principal: p}} = conn, %{"id" => id}) do
    rows =
      {:account, p.account_id} |> Kumbukumbu.sessions() |> Enum.filter(&(&1.resident_id == id))

    json(conn, Enum.map(rows, &session/1))
  end

  operation(:create,
    summary: "Open a session, or return the main one between this account and the resident",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the kind", "application/json",
       %Schema{
         type: :object,
         properties: %{kind: %Schema{type: :string, enum: ["main", "free_time", "hands"]}}
       }},
    responses: [created: {"the session key", "application/json", %Schema{type: :object}}]
  )

  def create(conn, %{"id" => id} = params) do
    {party, adapter_name} = party_of(conn, id)

    result =
      case {Map.get(params, "kind", "main"), adapter(conn)} do
        {"main", nil} -> Kumbukumbu.main_session(id, party, actor(conn))
        {kind, _} -> Kumbukumbu.open_session(id, kind, adapter_name, [party], actor(conn))
      end

    case result do
      {:ok, key} -> conn |> put_status(201) |> json(%{key: key})
      {:error, %Kumbukumbu.Error{} = e} -> error(conn, 422, e)
      {:error, reason} -> problem(conn, 422, :session_not_opened, inspect(reason))
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
        json(conn, %{session: session(s), messages: Enum.map(messages, &message/1)})

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

  def turn(conn, %{"id" => id, "key" => key, "text" => text}) when is_binary(text) do
    case Oneiroi.Brain.turn(id, key, text, actor(conn)) do
      {:ok, turn} ->
        conn |> put_status(201) |> json(turn)

      {:error, {%{kind: :nisaba_budget_exceeded} = stop, turn}} ->
        conn |> put_status(402) |> json(Map.put(turn, :stopped, stop_body(stop)))

      {:error, %{kind: _} = e} ->
        error(conn, 502, e)

      {:error, reason} ->
        problem(conn, 422, :turn_not_run, inspect(reason))
    end
  end

  def turn(conn, _params), do: problem(conn, 422, :text_required, "text is required")

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

  def search(conn, _params), do: problem(conn, 422, :query_required, "q is required")

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
      :ok -> send_resp(conn, 204, "")
      {:error, %Kumbukumbu.Error{} = e} -> error(conn, 404, e)
      {:error, {:refused, problems}} -> problem(conn, 422, :refused, inspect(problems))
      {:error, reason} -> problem(conn, 422, :not_resolved, inspect(reason))
    end
  end

  def resolve(conn, _params),
    do: problem(conn, 422, :fields_required, "key, how and note are required")

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

    with {:ok, started_at, _} <- parse_started(started),
         {:ok, built} <- build_messages(messages, actor(conn)),
         :ok <- Kumbukumbu.capture(id, key, turn_ref, started_at, built, actor(conn)) do
      conn |> put_status(201) |> json(%{turn_ref: turn_ref})
    else
      {:error, %Kumbukumbu.Error{} = e} ->
        error(conn, 404, e)

      {:error, :message_invalid} ->
        problem(conn, 422, :message_invalid, "each message needs a role and content")

      {:error, reason} ->
        problem(conn, 422, :not_captured, inspect(reason))
    end
  end

  def capture(conn, _params),
    do: problem(conn, 422, :fields_required, "session_key, started_at and messages are required")

  defp parse_started(iso) when is_binary(iso), do: DateTime.from_iso8601(iso)
  defp parse_started(_other), do: {:error, :started_at_invalid}

  operation(:turn_start,
    summary: "An adapter reports a turn beginning (spec §8) and gets the ref to capture it under",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the session", "application/json",
       %Schema{
         type: :object,
         required: [:session_key],
         properties: %{session_key: %Schema{type: :string}}
       }},
    responses: [created: {"the turn ref", "application/json", %Schema{type: :object}}]
  )

  def turn_start(conn, %{"id" => id, "session_key" => key}) do
    turn_ref = Kumbukumbu.turn_ref()

    case Kumbukumbu.start_turn(id, key, turn_ref, actor(conn)) do
      :ok ->
        conn |> put_status(201) |> json(%{turn_ref: turn_ref})

      {:error, :no_such_session} ->
        error(conn, 404, Kumbukumbu.Error.new(:kumbukumbu_no_such_session, key: key))

      {:error, reason} ->
        problem(conn, 422, :turn_not_started, inspect(reason))
    end
  end

  def turn_start(conn, _params),
    do: problem(conn, 422, :session_key_required, "session_key is required")

  operation(:context,
    summary:
      "What the platform would put in front of its own brain this turn (spec §8): the index and how I act, as text for an adapter to inject",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the context", "application/json", %Schema{type: :object}}]
  )

  def context(conn, %{"id" => id}) do
    index = Kumbukumbu.index(id)
    json(conn, %{text: index.text, bookmarks: index.included, left_out: index.left_out})
  end

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
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_witnessed)) |> halt()
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

    if :invalid in built, do: {:error, :message_invalid}, else: {:ok, built}
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

  defp session(s) do
    %{
      key: s.key,
      resident_id: s.resident_id,
      kind: s.kind,
      adapter: s.adapter,
      participants: s.participants,
      shared: s.shared,
      opened_at: s.opened_at,
      last_turn_at: s.last_turn_at,
      turns: s.turns,
      summary: s.summary,
      compacted_through: s.compacted_through
    }
  end

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
