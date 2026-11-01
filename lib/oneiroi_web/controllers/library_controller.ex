defmodule OneiroiWeb.LibraryController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["library"])

  plug(:witnessed)

  operation(:index,
    summary:
      "The library: the kinds registry, every registered document with its status, the files waiting to be adopted, the latest index runs",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the library", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}) do
    json(conn, %{
      kinds: Seshat.kinds(),
      documents: id |> Seshat.documents() |> Enum.map(&document/1),
      unadopted: Seshat.unadopted(id),
      runs: id |> Seshat.index_runs(5) |> Enum.map(&run/1)
    })
  end

  operation(:show,
    summary: "A document: its row, its content, its references resolved now, its discussions",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    responses: [ok: {"the document", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id, "path" => path}) do
    path = Enum.join(path, "/")

    case Seshat.document(id, path) do
      {:ok, %{document: row, content: content, discussions: discussions}} ->
        json(conn, %{
          document: document(row),
          content: content,
          references: Seshat.references(id, path),
          discussions:
            Enum.map(discussions, &%{session_key: &1.session_key, opened_at: &1.opened_at})
        })

      other ->
        respond(conn, other)
    end
  end

  operation(:write,
    summary: "Write a file through the flow; the path says the kind; the index runs",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    request_body:
      {"the file", "application/json",
       %Schema{
         type: :object,
         required: [:content],
         properties: %{content: %Schema{type: :string}}
       }},
    responses: [ok: {"what happened", "application/json", %Schema{type: :object}}]
  )

  def write(conn, %{"id" => id, "path" => path} = params) do
    case Seshat.write(id, Enum.join(path, "/"), to_string(params["content"] || ""), actor(conn)) do
      {:ok, result} -> json(conn, result)
      other -> respond(conn, other)
    end
  end

  operation(:adopt,
    summary: "Adopt a file made outside the flow, as it is",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the file", "application/json",
       %Schema{type: :object, required: [:path], properties: %{path: %Schema{type: :string}}}},
    responses: [ok: {"what happened", "application/json", %Schema{type: :object}}]
  )

  def adopt(conn, %{"id" => id} = params) do
    case Seshat.adopt(id, to_string(params["path"] || ""), actor(conn)) do
      {:ok, result} -> json(conn, result)
      other -> respond(conn, other)
    end
  end

  operation(:review,
    summary:
      "The review copy of a piece: the content with every reference resolved, and the references",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    responses: [ok: {"the review", "application/json", %Schema{type: :object}}]
  )

  def review(conn, %{"id" => id, "path" => path}) do
    case Seshat.review(id, Enum.join(path, "/")) do
      {:ok, review} -> json(conn, review)
      other -> respond(conn, other)
    end
  end

  operation(:publish_copy,
    summary: "The copy for publishing: frontmatter and citations stripped",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    responses: [ok: {"the copy", "application/json", %Schema{type: :object}}]
  )

  def publish_copy(conn, %{"id" => id, "path" => path}) do
    case Seshat.publish_copy(id, Enum.join(path, "/")) do
      {:ok, text} -> json(conn, %{content: text})
      other -> respond(conn, other)
    end
  end

  operation(:publish,
    summary: "Publish a piece at a URL (the witness's)",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the publication", "application/json",
       %Schema{
         type: :object,
         required: [:path, :url],
         properties: %{path: %Schema{type: :string}, url: %Schema{type: :string}}
       }},
    responses: [no_content: "published"]
  )

  def publish(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Seshat.publish(id, to_string(params["path"] || ""), params["url"], actor(conn))
      )

  operation(:discuss,
    summary: "Link a session to a piece as its discussion",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the link", "application/json",
       %Schema{
         type: :object,
         required: [:path, :session_key],
         properties: %{path: %Schema{type: :string}, session_key: %Schema{type: :string}}
       }},
    responses: [no_content: "linked"]
  )

  def discuss(conn, %{"id" => id} = params),
    do:
      respond(
        conn,
        Seshat.discuss(
          id,
          to_string(params["path"] || ""),
          to_string(params["session_key"] || ""),
          actor(conn)
        )
      )

  operation(:run_index,
    summary: "Run the index now",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the run", "application/json", %Schema{type: :object}}]
  )

  def run_index(conn, %{"id" => id}) do
    case Seshat.index(id, actor(conn)) do
      {:ok, figures} -> json(conn, figures)
      other -> respond(conn, other)
    end
  end

  operation(:search,
    summary: "Search the index: the nearest chunks to the query",
    parameters: [id: [in: :path, type: :string], q: [in: :query, type: :string]],
    responses: [ok: {"hits", "application/json", %Schema{type: :array}}]
  )

  def search(conn, %{"id" => id} = params) do
    case Seshat.search(id, to_string(params["q"] || ""), actor(conn)) do
      {:ok, hits} -> json(conn, hits)
      other -> respond(conn, other)
    end
  end

  operation(:cited_by,
    summary: "The documents citing a target",
    parameters: [id: [in: :path, type: :string], target: [in: :query, type: :string]],
    responses: [ok: {"references", "application/json", %Schema{type: :array}}]
  )

  def cited_by(conn, %{"id" => id} = params),
    do: json(conn, Seshat.cited_by(id, to_string(params["target"] || "")))

  # ---- shapes ----

  defp document(d) do
    %{
      path: d.path,
      kind: d.kind,
      origin: d.origin,
      title: d.title,
      status: d.status,
      bytes: d.bytes,
      versions: d.versions,
      chunks: d.chunks,
      indexed_at: d.indexed_at,
      missing_at: d.missing_at,
      written_at: d.written_at,
      written_by: d.written_by_kind,
      published_url: d.published_url,
      published_at: d.published_at
    }
  end

  defp run(r) do
    %{
      at: r.at,
      outcome: r.outcome,
      reason: r.reason,
      model: r.model,
      scanned: r.scanned,
      embedded: r.embedded,
      chunks: r.chunks,
      missing: r.missing,
      by: r.by_kind
    }
  end

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_witnessed)) |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:seshat_no_such_document, :seshat_no_such_file],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)

  defp respond(conn, {:error, reason}),
    do: problem(conn, 422, :refused, :web_library_respond_refused, inspect(reason))
end
