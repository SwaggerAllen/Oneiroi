defmodule OneiroiWeb.CorrespondenceController do
  @moduledoc """
  Correspondence's routes (xenia, spec §6.6, F23). The witness reads
  everything here and decides. An adapter's token with the `reader` role
  (the inbound hands, never the resident) delivers messages, reads the
  approved replies and marks one sent, and nothing else; a `brain`
  token is refused, so the resident cannot read past the gate.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Xenia
  alias OpenApiSpex.Schema

  tags(["correspondence"])

  # What the reader's token may do here; RequirePrincipal lets its
  # requests through to these three alone.
  @reader_actions ~w(receive replies sent)a

  plug(:allowed)

  @message %Schema{
    type: :object,
    required: [:platform, :account, :external_id, :sender, :text, :sent_at],
    properties: %{
      platform: %Schema{type: :string, description: "a lowercase slug: email, substack, …"},
      account: %Schema{type: :string, description: "the resident's own address on the platform"},
      external_id: %Schema{type: :string, description: "the platform's id for the message"},
      sender: %Schema{type: :string, description: "the sender's identity on the platform"},
      sender_name: %Schema{type: :string, nullable: true},
      verified: %Schema{
        type: :boolean,
        description:
          "whether the adapter verified the sender (a DMARC pass, a signed-in platform)"
      },
      thread: %Schema{type: :string, nullable: true},
      subject: %Schema{type: :string, nullable: true},
      text: %Schema{type: :string},
      sent_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @decision {"decision", "application/json",
             %Schema{
               type: :object,
               required: [:approve, :note],
               properties: %{approve: %Schema{type: :boolean}, note: %Schema{type: :string}}
             }}

  operation(:index,
    summary: "Messages, newest first; `state` narrows to pending, approved or rejected",
    parameters: [id: [in: :path, type: :string], state: [in: :query, type: :string]],
    responses: [ok: {"messages", "application/json", %Schema{type: :array}}]
  )

  def index(conn, %{"id" => id} = params),
    do: json(conn, id |> Xenia.messages(params["state"]) |> Enum.map(&message_json/1))

  operation(:receive,
    summary:
      "Deliver messages (at most 40): the reader adapter, or the witness pasting one; a message received before answers duplicate",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"delivery", "application/json",
       %Schema{type: :object, properties: %{messages: %Schema{type: :array, items: @message}}}},
    responses: [
      ok:
        {"each message's number, or duplicate, or its refusal", "application/json",
         %Schema{type: :array}}
    ]
  )

  def receive(conn, %{"id" => id} = params) do
    list = params |> Map.get("messages", []) |> List.wrap() |> Enum.map(&message_attrs/1)

    case Xenia.receive_messages(id, list, actor_of(conn)) do
      {:ok, results} -> json(conn, Enum.map(results, &result_json/1))
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:decide,
    summary: "Approve or reject a waiting message, with a note the resident reads first",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body: @decision,
    responses: [no_content: "decided"]
  )

  def decide(conn, %{"id" => id, "number" => n} = params),
    do:
      respond(
        conn,
        Xenia.decide_message(
          id,
          integer(n),
          params["approve"] == true,
          params["note"],
          actor_of(conn)
        )
      )

  operation(:correspondents,
    summary: "The trusted correspondents: whose messages reach the resident without your reading",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"correspondents", "application/json", %Schema{type: :array}}]
  )

  def correspondents(conn, %{"id" => id}) do
    json(
      conn,
      Enum.map(Xenia.correspondents(id), fn c ->
        %{
          platform: c.platform,
          identity: c.identity,
          name: c.name,
          note: c.note,
          trusted_at: c.trusted_at
        }
      end)
    )
  end

  operation(:trust,
    summary:
      "Trust an identity on a platform, with a note; only a verified sender is let through",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"correspondent", "application/json",
       %Schema{
         type: :object,
         required: [:platform, :identity, :note],
         properties: %{
           platform: %Schema{type: :string},
           identity: %Schema{type: :string},
           name: %Schema{type: :string, nullable: true},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "trusted"]
  )

  def trust(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Xenia.trust(
          id,
          params["platform"],
          params["identity"],
          params["name"],
          params["note"],
          actor_of(conn)
        )
      )

  operation(:distrust,
    summary: "Withdraw trust from an identity, with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"correspondent", "application/json",
       %Schema{
         type: :object,
         required: [:platform, :identity, :note],
         properties: %{
           platform: %Schema{type: :string},
           identity: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "withdrawn"]
  )

  def distrust(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Xenia.distrust(id, params["platform"], params["identity"], params["note"], actor_of(conn))
      )

  operation(:replies,
    summary:
      "The resident's replies, newest first; `state` narrows to drafted, approved, declined or sent. The reader adapter reads the approved ones alone",
    parameters: [id: [in: :path, type: :string], state: [in: :query, type: :string]],
    responses: [ok: {"replies", "application/json", %Schema{type: :array}}]
  )

  def replies(conn, %{"id" => id} = params) do
    state = if adapter(conn), do: "approved", else: params["state"]
    json(conn, id |> Xenia.replies(state) |> Enum.map(&reply_json/1))
  end

  operation(:decide_reply,
    summary: "Approve or decline a drafted reply, with a note",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body: @decision,
    responses: [no_content: "decided"]
  )

  def decide_reply(conn, %{"id" => id, "number" => n} = params),
    do:
      respond(
        conn,
        Xenia.decide_reply(
          id,
          integer(n),
          params["approve"] == true,
          params["note"],
          actor_of(conn)
        )
      )

  operation(:sent,
    summary: "Mark an approved reply sent, with where it now is: the receipt",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"receipt", "application/json",
       %Schema{type: :object, properties: %{url: %Schema{type: :string, nullable: true}}}},
    responses: [no_content: "marked"]
  )

  def sent(conn, %{"id" => id, "number" => n} = params),
    do: respond(conn, Xenia.mark_sent(id, integer(n), params["url"], actor_of(conn)))

  # ---- shapes ----

  defp message_attrs(m) when is_map(m) do
    sent_at =
      case DateTime.from_iso8601(to_string(m["sent_at"] || "")) do
        {:ok, at, _offset} -> at
        _other -> nil
      end

    %{
      platform: m["platform"],
      account: m["account"],
      external_id: m["external_id"] && to_string(m["external_id"]),
      sender: m["sender"],
      sender_name: m["sender_name"],
      verified: m["verified"] == true,
      thread: m["thread"] && to_string(m["thread"]),
      subject: m["subject"],
      text: m["text"],
      sent_at: sent_at
    }
  end

  defp message_attrs(_other), do: %{}

  defp result_json({:ok, :duplicate}), do: %{duplicate: true}
  defp result_json({:ok, n}), do: %{number: n}

  defp result_json({:error, %{kind: kind, meaning: meaning}}),
    do: %{error: %{kind: kind, meaning: meaning}}

  defp message_json(m) do
    Map.take(m, [
      :number,
      :platform,
      :account,
      :external_id,
      :sender,
      :sender_name,
      :verified,
      :thread,
      :subject,
      :text,
      :sent_at,
      :received_at,
      :state,
      :trusted,
      :note,
      :decided_at,
      :read_at
    ])
  end

  defp reply_json(r) do
    Map.take(r, [
      :number,
      :in_reply_to,
      :platform,
      :account,
      :thread,
      :to,
      :text,
      :state,
      :note,
      :drafted_at,
      :decided_at,
      :sent_at,
      :sent_by,
      :url
    ])
  end

  # ---- who ----

  # The reader's actions are recorded as the hands that did them, named
  # by the adapter; the witness's as the witness.
  defp actor_of(%{assigns: %{principal: %AdapterPrincipal{adapter: name}}}),
    do: Actor.new(:hands, name)

  defp actor_of(conn), do: actor(conn)

  defp allowed(%{params: %{"id" => id}} = conn, _opts) do
    ok? =
      case adapter(conn) do
        %AdapterPrincipal{resident_id: ^id, role: "reader"} ->
          Phoenix.Controller.action_name(conn) in @reader_actions

        %AdapterPrincipal{} ->
          false

        nil ->
          witnesses?(conn, id)
      end

    if ok?,
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_correspondence_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:xenia_no_such_message, :xenia_no_such_reply, :xenia_no_such_correspondent],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> 0
    end
  end
end
