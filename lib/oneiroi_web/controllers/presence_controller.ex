defmodule OneiroiWeb.PresenceController do
  @moduledoc """
  Presence on Substack (xenia#20). The witness turns it on and names the
  handle, fetches the follow list and keeps its mask, reads the passes,
  and decides each staged interaction: approve, revise (with how) or
  pass. The `reader` adapter reads what is due to go out, with the words
  and the origin each is sent from, and says it went or failed; a
  `brain` token is refused, since the resident reads and stages through
  her own tools.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Xenia
  alias OpenApiSpex.Schema

  tags(["presence"])

  @reader_actions ~w(due sent failed)a

  plug(:allowed)

  @object %Schema{type: :object}

  operation(:show,
    summary:
      "Presence: the switch and handle, the follow list with its mask and last samples, the latest passes with their reads, and the interactions",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"presence", "application/json", @object}]
  )

  def show(conn, %{"id" => id}) do
    json(conn, %{
      settings: Xenia.presence(id),
      accounts: Enum.map(Xenia.presence_accounts(id), &account_json/1),
      passes: Enum.map(Xenia.presence_passes(id, 7), &pass_json/1),
      interactions: Enum.map(Xenia.presence_interactions(id, nil), &interaction_json/1)
    })
  end

  operation(:set,
    summary:
      "The witness turns presence on or off and names the Substack handle whose subscriptions it reads",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the switch", "application/json",
       %Schema{
         type: :object,
         required: [:enabled, :handle],
         properties: %{enabled: %Schema{type: :boolean}, handle: %Schema{type: :string}}
       }},
    responses: [no_content: "set"]
  )

  def set(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Xenia.set_presence(id, params["enabled"] == true, params["handle"], actor(conn))
      )

  operation(:refresh,
    summary:
      "Fetches the follow list again, recorded only when it matches the count the profile claims",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"how many accounts", "application/json", @object}]
  )

  def refresh(conn, %{"id" => id}) do
    case Xenia.refresh_follows(id, actor(conn)) do
      {:ok, n} -> json(conn, %{accounts: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:exclude,
    summary:
      "The witness masks an account from the rotation, with a one-line reason; the follow stays",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"the reason", "application/json",
       %Schema{type: :object, required: [:reason], properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "masked"]
  )

  def exclude(conn, %{"id" => id, "key" => key} = params),
    do: respond(conn, Xenia.exclude_account(id, key, params["reason"], actor(conn)))

  operation(:include,
    summary: "The witness lifts a mask, with a note",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "unmasked"]
  )

  def include(conn, %{"id" => id, "key" => key} = params),
    do: respond(conn, Xenia.include_account(id, key, params["note"], actor(conn)))

  operation(:decide,
    summary:
      "The witness decides a staged interaction: approve (released at a random instant later), revise (with the comment that says how) or pass; a comment is optional otherwise",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the decision", "application/json",
       %Schema{
         type: :object,
         required: [:decision],
         properties: %{
           decision: %Schema{type: :string, enum: ["approve", "revise", "pass"]},
           comment: %Schema{type: :string}
         }
       }},
    responses: [no_content: "decided"]
  )

  def decide(conn, %{"id" => id, "number" => n} = params),
    do:
      respond(
        conn,
        Xenia.decide_interaction(
          id,
          integer(n),
          to_string(params["decision"] || ""),
          params["comment"],
          actor(conn)
        )
      )

  operation(:due,
    summary:
      "What the reader sends now: approved interactions whose release has come, each with its action, target, id, the origin it goes from and a comment's words",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"due", "application/json", %Schema{type: :array}}]
  )

  def due(conn, %{"id" => id}), do: json(conn, Xenia.presence_due(id))

  operation(:sent,
    summary: "An interaction went out, with its address if Substack gave one",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the receipt", "application/json",
       %Schema{type: :object, properties: %{url: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def sent(conn, %{"id" => id, "number" => n} = params),
    do: respond(conn, Xenia.interaction_sent(id, integer(n), params["url"], actor_of(conn)))

  operation(:failed,
    summary: "An interaction could not go out, and why",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:reason], properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def failed(conn, %{"id" => id, "number" => n} = params),
    do:
      respond(
        conn,
        Xenia.interaction_failed(
          id,
          integer(n),
          to_string(params["reason"] || "no reason given"),
          actor_of(conn)
        )
      )

  defp respond(conn, :ok), do: send_resp(conn, 204, "")
  defp respond(conn, {:error, e}), do: error(conn, 422, e)

  defp account_json(a),
    do: %{
      key: a.key,
      name: a.name,
      host: a.host,
      followed: a.followed,
      excluded: a.excluded,
      excluded_at: a.excluded_at,
      reason: a.reason,
      first_seen_at: a.first_seen_at,
      last_sampled_at: a.last_sampled_at
    }

  defp pass_json(%{pass: p, reads: reads}),
    do: %{
      number: p.number,
      day: p.day,
      accounts: p.accounts,
      pool: p.pool,
      ranked: p.ranked,
      serendipity: p.serendipity,
      cap: p.cap,
      drawn_at: p.drawn_at,
      reads: Enum.map(reads, &read_json/1)
    }

  defp read_json(nil), do: nil

  defp read_json(r),
    do: %{
      item: r.item,
      account: r.account,
      kind: r.kind,
      title: r.title,
      url: r.url,
      published_at: r.published_at,
      likes: r.likes,
      comments: r.comments,
      restacks: r.restacks,
      score: r.score,
      cut: r.cut,
      excerpt: r.excerpt,
      read_at: r.read_at
    }

  defp interaction_json(%{interaction: i, read: r}),
    do: %{
      number: i.number,
      pass: i.pass,
      item: i.item,
      account: i.account,
      kind: i.kind,
      text: i.text,
      supersedes: i.supersedes,
      superseded_by: i.superseded_by,
      state: i.state,
      comment: i.comment,
      release_at: i.release_at,
      staged_at: i.staged_at,
      decided_at: i.decided_at,
      sent_at: i.sent_at,
      url: i.url,
      reason: i.reason,
      read: read_json(r)
    }

  defp integer(n) when is_integer(n), do: n

  defp integer(n) do
    case Integer.parse(to_string(n)) do
      {i, ""} -> i
      _ -> 0
    end
  end

  defp actor_of(%{assigns: %{principal: %AdapterPrincipal{adapter: name}}}),
    do: Actor.new(:hands, name)

  defp actor_of(conn), do: actor(conn)

  defp allowed(%{params: %{"id" => id}} = conn, _opts) do
    action = Phoenix.Controller.action_name(conn)

    ok? =
      case adapter(conn) do
        %AdapterPrincipal{resident_id: ^id, role: "reader"} -> action in @reader_actions
        %AdapterPrincipal{} -> false
        nil -> witnesses?(conn, id)
      end

    if ok?,
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_presence_not_witnessed
          )
        )
        |> halt()
  end
end
