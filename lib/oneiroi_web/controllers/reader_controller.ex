defmodule OneiroiWeb.ReaderController do
  @moduledoc """
  The reader's allowlists (xenia#16), research (seshat#38) and digests
  (seshat#40). The
  witness reads and sets the two allowlists, asks research and reads it;
  the `reader` adapter reads the allowlists, the open questions, and
  answers or fails one. A `brain` token is refused: the resident asks
  through her tool, which says what the reader may reach.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias Oneiroi.Xenia
  alias OpenApiSpex.Schema

  tags(["reader"])

  @reader_actions ~w(sites research answer failed digests answer_digest fail_digest pieces piece_drafted piece_published externals external_fetched external_failed)a

  plug(:allowed)
  # The contract's switches (agathos-daimon#34), after the party check.
  plug(OneiroiWeb.Plugs.Switch, [key: "research"] when action in [:ask])
  plug(OneiroiWeb.Plugs.Switch, [key: "digests"] when action in [:ask_digest])

  @list %Schema{type: :array, items: %Schema{type: :string}}

  operation(:sites,
    summary:
      "The reader's two allowlists: the origins its browser may reach to read correspondence (`scrape`) and to research (`research`); `*` for any",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the allowlists", "application/json", %Schema{type: :object}}]
  )

  def sites(conn, %{"id" => id}), do: json(conn, Xenia.reader_sites(id))

  operation(:set_sites,
    summary: "Sets the reader's two allowlists, each at most 50 origins (https://host) or *",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the allowlists", "application/json",
       %Schema{type: :object, properties: %{scrape: @list, research: @list}}},
    responses: [ok: {"the allowlists", "application/json", %Schema{type: :object}}]
  )

  def set_sites(conn, %{"id" => id} = params) do
    case Xenia.set_reader_sites(
           id,
           strings(params["scrape"]),
           strings(params["research"]),
           actor(conn)
         ) do
      :ok -> json(conn, Xenia.reader_sites(id))
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:research,
    summary:
      "Research questions, newest first. The reader is given the open ones alone; `status` narrows for the witness",
    parameters: [id: [in: :path, type: :string], status: [in: :query, type: :string]],
    responses: [ok: {"questions", "application/json", %Schema{type: :array}}]
  )

  def research(conn, %{"id" => id} = params) do
    status = if adapter(conn), do: "open", else: params["status"]
    opts = if status, do: [status: status], else: []
    json(conn, id |> Seshat.researches(opts) |> Enum.map(&research_json/1))
  end

  operation(:ask,
    summary:
      "The witness asks the reader's research pass a named question, with up to ten pages to start from",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the question", "application/json",
       %Schema{
         type: :object,
         required: [:question],
         properties: %{question: %Schema{type: :string}, urls: @list}
       }},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def ask(conn, %{"id" => id} = params) do
    case Seshat.ask_research(
           id,
           nil,
           to_string(params["question"] || ""),
           strings(params["urls"]),
           actor(conn)
         ) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:answer,
    summary:
      "The reader answers a research question: a summary and a note per page read, written under research/",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"what it found", "application/json",
       %Schema{
         type: :object,
         properties: %{
           summary: %Schema{type: :string},
           sources: %Schema{type: :array, items: %Schema{type: :object}}
         }
       }},
    responses: [ok: {"the folder", "application/json", %Schema{type: :object}}]
  )

  def answer(conn, %{"id" => id, "number" => n} = params) do
    found = %{summary: params["summary"], sources: List.wrap(params["sources"])}

    case Seshat.answer_research(id, integer(n), found, actor_of(conn)) do
      {:ok, path} -> json(conn, %{path: path})
      {:error, %{kind: :seshat_no_such_research} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:failed,
    summary: "The reader could not do a research question, and says why",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def failed(conn, %{"id" => id, "number" => n} = params) do
    case Seshat.fail_research(
           id,
           integer(n),
           to_string(params["reason"] || "no reason given"),
           actor_of(conn)
         ) do
      :ok -> send_resp(conn, 204, "")
      {:error, %{kind: :seshat_no_such_research} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  # ---- external sources (seshat#46) ----

  operation(:externals,
    summary:
      "External sources commissioned for citing, newest first. The reader is given those waiting for a copy alone, with what to fetch; `status` narrows for the witness",
    parameters: [id: [in: :path, type: :string], status: [in: :query, type: :string]],
    responses: [ok: {"sources", "application/json", %Schema{type: :array}}]
  )

  def externals(conn, %{"id" => id} = params) do
    status = if adapter(conn), do: "asked", else: params["status"]
    opts = if status, do: [status: status], else: []
    json(conn, id |> Seshat.externals(opts) |> Enum.map(&external_json/1))
  end

  operation(:commission_external,
    summary:
      "The witness commissions a source for citing by its URL: a web page, or a GitHub file; the reader fetches its first copy",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the source", "application/json",
       %Schema{type: :object, required: [:url], properties: %{url: %Schema{type: :string}}}},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def commission_external(conn, %{"id" => id} = params) do
    case Seshat.commission_external(id, nil, to_string(params["url"] || ""), actor(conn)) do
      {:ok, n, state} -> conn |> put_status(201) |> json(%{number: n, state: state})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:fetch_external,
    summary: "The witness asks the reader for a fresh copy of a source",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    responses: [ok: {"asked or already waiting", "application/json", %Schema{type: :object}}]
  )

  def fetch_external(conn, %{"id" => id, "number" => n}) do
    case Seshat.fetch_external(id, nil, integer(n), actor(conn)) do
      {:ok, state} -> json(conn, %{state: state})
      {:error, %{kind: :seshat_no_such_external} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:external_fetched,
    summary:
      "The reader brings a source's copy: its words as markdown, its title, and a document's commit; kept whole under external/",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the copy", "application/json",
       %Schema{
         type: :object,
         required: [:text],
         properties: %{
           text: %Schema{type: :string},
           title: %Schema{type: :string},
           commit: %Schema{type: :string}
         }
       }},
    responses: [ok: {"the path", "application/json", %Schema{type: :object}}]
  )

  def external_fetched(conn, %{"id" => id, "number" => n} = params) do
    copy = %{text: params["text"], title: params["title"], commit: params["commit"]}

    case Seshat.external_fetched(id, integer(n), copy, actor_of(conn)) do
      {:ok, :not_asked} -> json(conn, %{path: nil, state: "not_asked"})
      {:ok, path} -> json(conn, %{path: path})
      {:error, %{kind: :seshat_no_such_external} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:external_failed,
    summary: "The reader could not fetch a source, and says why",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def external_failed(conn, %{"id" => id, "number" => n} = params) do
    case Seshat.external_failed(
           id,
           integer(n),
           to_string(params["reason"] || "no reason given"),
           actor_of(conn)
         ) do
      :ok -> send_resp(conn, 204, "")
      {:error, %{kind: :seshat_no_such_external} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp external_json(x),
    do:
      Map.take(x, [
        :number,
        :kind,
        :key,
        :url,
        :ref,
        :title,
        :status,
        :path,
        :content_hash,
        :previous_hash,
        :commit,
        :bytes,
        :fetches,
        :reason,
        :commissioned_by,
        :commissioned_at,
        :asked_at,
        :fetched_at,
        :previous_fetched_at
      ])

  # ---- digests (seshat#40) ----

  operation(:pieces,
    summary:
      "The writing gate's work for the reader (seshat#42): approved pieces to make a Substack draft of, with title and copy, and drafted ones to watch for the witness's Publish",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"pieces", "application/json", %Schema{type: :object}}]
  )

  def pieces(conn, %{"id" => id}), do: json(conn, Seshat.pieces_for_reader(id))

  operation(:piece_drafted,
    summary: "The reader made a Substack draft of an approved piece, at this URL",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the draft", "application/json",
       %Schema{
         type: :object,
         required: [:path, :url],
         properties: %{path: %Schema{type: :string}, url: %Schema{type: :string}}
       }},
    responses: [no_content: "recorded"]
  )

  def piece_drafted(conn, %{"id" => id} = params) do
    case Seshat.piece_drafted(id, to_string(params["path"] || ""), params["url"], actor_of(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:piece_published,
    summary: "The reader found a drafted piece published at this URL; the piece records it",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the post", "application/json",
       %Schema{
         type: :object,
         required: [:path, :url],
         properties: %{path: %Schema{type: :string}, url: %Schema{type: :string}}
       }},
    responses: [no_content: "recorded"]
  )

  def piece_published(conn, %{"id" => id} = params) do
    case Seshat.piece_published(
           id,
           to_string(params["path"] || ""),
           params["url"],
           actor_of(conn)
         ) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:digests,
    summary:
      "Digests asked of the reader, newest first, each with the instant it covers from. The reader is given the open one alone",
    parameters: [id: [in: :path, type: :string], status: [in: :query, type: :string]],
    responses: [ok: {"digests", "application/json", %Schema{type: :array}}]
  )

  def digests(conn, %{"id" => id} = params) do
    status = if adapter(conn), do: "open", else: params["status"]
    opts = if status, do: [status: status], else: []
    json(conn, id |> Seshat.digests(opts) |> Enum.map(&digest_json/1))
  end

  operation(:ask_digest,
    summary:
      "The witness asks the reader for a digest of the resident's streams since the last one; the open one's number if one is open",
    parameters: [id: [in: :path, type: :string]],
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def ask_digest(conn, %{"id" => id}) do
    case Seshat.ask_digest(id, nil, actor(conn)) do
      {:ok, n, state} -> conn |> put_status(201) |> json(%{number: n, state: state})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:answer_digest,
    summary:
      "The reader answers a digest: a summary and an item per piece read (source, title, link, notes in its own words), written under feeds/digests/",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"what it read", "application/json",
       %Schema{
         type: :object,
         properties: %{
           summary: %Schema{type: :string},
           items: %Schema{type: :array, items: %Schema{type: :object}}
         }
       }},
    responses: [ok: {"the file", "application/json", %Schema{type: :object}}]
  )

  def answer_digest(conn, %{"id" => id, "number" => n} = params) do
    found = %{summary: params["summary"], items: List.wrap(params["items"])}

    case Seshat.answer_digest(id, integer(n), found, actor_of(conn)) do
      {:ok, path} -> json(conn, %{path: path})
      {:error, %{kind: :seshat_no_such_digest} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:fail_digest,
    summary: "The reader could not compile a digest, and says why",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def fail_digest(conn, %{"id" => id, "number" => n} = params) do
    case Seshat.fail_digest(
           id,
           integer(n),
           to_string(params["reason"] || "no reason given"),
           actor_of(conn)
         ) do
      :ok -> send_resp(conn, 204, "")
      {:error, %{kind: :seshat_no_such_digest} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp digest_json(d),
    do:
      Map.take(d, [
        :number,
        :since,
        :asked_by,
        :status,
        :path,
        :items,
        :reason,
        :asked_at,
        :settled_at
      ])

  defp research_json(r),
    do:
      Map.take(r, [
        :number,
        :question,
        :urls,
        :sources,
        :asked_by,
        :status,
        :path,
        :reason,
        :asked_at,
        :settled_at
      ])

  defp strings(list) when is_list(list),
    do: list |> Enum.map(&String.trim(to_string(&1))) |> Enum.reject(&(&1 == ""))

  defp strings(_other), do: []

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
        %AdapterPrincipal{resident_id: ^id, role: "reader"} ->
          action in @reader_actions

        %AdapterPrincipal{} ->
          false

        nil ->
          witnesses?(conn, id) and
            action not in [
              :answer,
              :failed,
              :answer_digest,
              :fail_digest,
              :external_fetched,
              :external_failed
            ]
      end

    if ok?,
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_reader_not_witnessed
          )
        )
        |> halt()
  end
end
