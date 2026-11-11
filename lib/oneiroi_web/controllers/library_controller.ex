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
      # Her shelf (seshat#51): the system's kinds, then her own, whose
      # folders the Records tree shows.
      kinds: Seshat.kinds(id),
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
          # The witness's edit lease on it, held or taken, or null
          # (seshat#55): shown to both parties.
          lease: Seshat.lease(id, path),
          references: Seshat.references(id, path),
          discussions:
            Enum.map(discussions, &%{session_key: &1.session_key, opened_at: &1.opened_at})
        })

      other ->
        respond(conn, other)
    end
  end

  operation(:download,
    summary:
      "A document's file, raw (seshat#50): the bytes as the repository holds them, read the way the document view reads them, as an attachment, always bytes to save",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    responses: [ok: {"the file", "application/octet-stream", %Schema{type: :string}}]
  )

  def download(conn, %{"id" => id, "path" => path}) do
    path = Enum.join(path, "/")

    case Seshat.document(id, path) do
      {:ok, %{content: content}} ->
        # Always bytes to save, never a page to render: a document's
        # words are hers and the browser must not run them.
        send_download(conn, {:binary, content},
          filename: download_name(path),
          content_type: "application/octet-stream"
        )

      other ->
        respond(conn, other)
    end
  end

  # The file's own name, safe in a header.
  defp download_name(path),
    do: path |> Path.basename() |> String.replace(~r/[^A-Za-z0-9._-]/, "_")

  operation(:write,
    summary:
      "Write a file through the flow; the path says the kind; the index runs; `note` is what you say of this version (seshat#54), and a write to a path you hold a lease on renews it (seshat#55)",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    request_body:
      {"the file", "application/json",
       %Schema{
         type: :object,
         required: [:content],
         properties: %{content: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [ok: {"what happened", "application/json", %Schema{type: :object}}]
  )

  def write(conn, %{"id" => id, "path" => path} = params) do
    note = if is_binary(params["note"]), do: params["note"]

    case Seshat.write(
           id,
           Enum.join(path, "/"),
           to_string(params["content"] || ""),
           actor(conn),
           note: note
         ) do
      {:ok, result} -> json(conn, result)
      other -> respond(conn, other)
    end
  end

  operation(:paste,
    summary:
      "Paste a conversation of yours with another person into her human-correspondence/ (seshat#65): `with` (whom it is with) and an optional `title` start a new document, never over one there; `path` names one there to add to, under a dated heading (seshat#66). Written as you with a note; the index runs",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the paste", "application/json",
       %Schema{
         type: :object,
         required: [:text],
         properties: %{
           text: %Schema{type: :string},
           path: %Schema{type: :string},
           with: %Schema{type: :string},
           title: %Schema{type: :string}
         }
       }},
    responses: [ok: {"what happened", "application/json", %Schema{type: :object}}]
  )

  def paste(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ["text", "path", "with", "title"])

    case Seshat.paste_correspondence(id, attrs, actor(conn)) do
      {:ok, result} -> json(conn, result)
      other -> respond(conn, other)
    end
  end

  operation(:versions,
    summary:
      "A document's versions, newest first (seshat#54): each `{version (the words' SHA-256), act, at, actor {kind, id} | null, note, bytes, commit, committed_at, current, restorable}`, from the repository's history joined to the library's record of who wrote what; `current` is the hash of the file now. Identity files (SOUL.md and the rest) by name.",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    responses: [ok: {"the versions", "application/json", %Schema{type: :object}}]
  )

  def versions(conn, %{"id" => id, "path" => path}) do
    case Seshat.versions(id, Enum.join(path, "/")) do
      {:ok, versions} -> json(conn, versions)
      other -> respond(conn, other)
    end
  end

  operation(:version,
    summary: "One version's words, by its hash (seshat#54)",
    parameters: [
      id: [in: :path, type: :string],
      path: [in: :path, type: :string],
      version: [in: :query, type: :string]
    ],
    responses: [ok: {"the words", "application/json", %Schema{type: :object}}]
  )

  def version(conn, %{"id" => id, "path" => path} = params) do
    path = Enum.join(path, "/")

    case Seshat.version(id, path, params["version"]) do
      {:ok, content} -> json(conn, %{path: path, version: params["version"], content: content})
      other -> respond(conn, other)
    end
  end

  operation(:diff,
    summary:
      "The line diff between two versions (seshat#54): `from` a version's hash, `to` another or omitted for the file now; `{path, from, to, added, removed, runs: [{op: eq | del | ins, lines}]}`",
    parameters: [
      id: [in: :path, type: :string],
      path: [in: :path, type: :string],
      from: [in: :query, type: :string],
      to: [in: :query, type: :string]
    ],
    responses: [ok: {"the diff", "application/json", %Schema{type: :object}}]
  )

  def diff(conn, %{"id" => id, "path" => path} = params) do
    to = if params["to"] in [nil, ""], do: nil, else: params["to"]

    case Seshat.version_diff(id, Enum.join(path, "/"), params["from"], to) do
      {:ok, diff} -> json(conn, diff)
      other -> respond(conn, other)
    end
  end

  operation(:restore,
    summary:
      "Restore a version (seshat#54): the write the normal path makes, `{path, version, written}`; an identity file after first contact is filed as the soul-edit proposal instead, 202 with `{path, version, proposed: ref}`",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"which version", "application/json",
       %Schema{
         type: :object,
         required: [:path, :version],
         properties: %{
           path: %Schema{type: :string},
           version: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [
      ok: {"written", "application/json", %Schema{type: :object}},
      accepted: {"proposed", "application/json", %Schema{type: :object}}
    ]
  )

  def restore(conn, %{"id" => id} = params) do
    case Seshat.restore(
           id,
           to_string(params["path"] || ""),
           params["version"],
           params["note"],
           actor(conn)
         ) do
      {:ok, %{proposed: _} = proposed} -> conn |> put_status(202) |> json(proposed)
      {:ok, restored} -> json(conn, restored)
      other -> respond(conn, other)
    end
  end

  operation(:leases,
    summary: "The edit leases on the library, held or taken (seshat#55)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"leases", "application/json", %Schema{type: :array}}]
  )

  def leases(conn, %{"id" => id}), do: json(conn, Seshat.leases(id))

  operation(:acquire_lease,
    summary:
      "Acquire the edit lease on a path for your editor, or renew your own (seshat#55): `{path, holder_id, state, acquired_at, renewed_at, takeable_at, takeable, waiting_at, has_draft, taken_at, kept_at}`; 422 `seshat_lease_held` while another account holds it",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the path", "application/json",
       %Schema{type: :object, required: [:path], properties: %{path: %Schema{type: :string}}}},
    responses: [ok: {"the lease", "application/json", %Schema{type: :object}}]
  )

  def acquire_lease(conn, %{"id" => id} = params) do
    case Seshat.acquire_lease(id, to_string(params["path"] || ""), actor(conn)) do
      {:ok, lease} -> json(conn, lease)
      other -> respond(conn, other)
    end
  end

  operation(:renew_lease,
    summary:
      "Renew your lease while you write, with your unsaved draft (seshat#55); 409 `seshat_lease_taken` with `kept_at` once the resident's write took it",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the path and the draft", "application/json",
       %Schema{
         type: :object,
         required: [:path],
         properties: %{path: %Schema{type: :string}, draft: %Schema{type: :string}}
       }},
    responses: [ok: {"the lease", "application/json", %Schema{type: :object}}]
  )

  def renew_lease(conn, %{"id" => id} = params) do
    draft = if is_binary(params["draft"]), do: params["draft"]

    case Seshat.renew_lease(id, to_string(params["path"] || ""), draft, actor(conn)) do
      {:ok, lease} -> json(conn, lease)
      other -> respond(conn, other)
    end
  end

  operation(:release_lease,
    summary: "Release your lease on a path, held or taken (seshat#55)",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the path", "application/json",
       %Schema{type: :object, required: [:path], properties: %{path: %Schema{type: :string}}}},
    responses: [no_content: "released"]
  )

  def release_lease(conn, %{"id" => id} = params),
    do: respond(conn, Seshat.release_lease(id, to_string(params["path"] || ""), actor(conn)))

  operation(:remove,
    summary:
      "Remove a scratch or human document (seshat#33): recorded with you as its actor; every other kind is kept",
    parameters: [id: [in: :path, type: :string], path: [in: :path, type: :string]],
    responses: [no_content: "removed"]
  )

  def remove(conn, %{"id" => id, "path" => path}) do
    case Seshat.remove(id, Enum.join(path, "/"), actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      other -> respond(conn, other)
    end
  end

  operation(:move,
    summary:
      "Move a document from one path, and so one kind, to another, its bytes unchanged (seshat#39); a citation of the old path follows it, and nothing is overwritten",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"from and to", "application/json",
       %Schema{
         type: :object,
         required: [:from, :to],
         properties: %{from: %Schema{type: :string}, to: %Schema{type: :string}}
       }},
    responses: [ok: {"where it went", "application/json", %Schema{type: :object}}]
  )

  def move(conn, %{"id" => id, "from" => from, "to" => to})
      when is_binary(from) and is_binary(to) do
    case Seshat.move(id, from, to, actor(conn)) do
      {:ok, moved} -> json(conn, moved)
      other -> respond(conn, other)
    end
  end

  def move(conn, _params),
    do:
      respond(
        conn,
        {:error, Oneiroi.Seshat.Error.new(:seshat_path_invalid, :seshat_web_move_paths_required)}
      )

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
      # When it was first registered (seshat#48): the library's created.
      created_at: d.registered_at,
      written_by: d.written_by_kind,
      published_url: d.published_url,
      published_at: d.published_at,
      # Why a keepsake mattered, in the resident's words (seshat#32).
      note: d.note
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
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_library_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [
              :seshat_no_such_document,
              :seshat_no_such_version,
              :seshat_no_such_file,
              :seshat_not_adopted,
              :seshat_document_missing
            ],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: :seshat_lease_taken} = e}), do: error(conn, 409, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
end
