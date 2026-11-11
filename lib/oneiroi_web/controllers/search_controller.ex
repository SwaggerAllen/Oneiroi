defmodule OneiroiWeb.SearchController do
  @moduledoc """
  The one search (kumbukumbu#59, spec F66): `GET /v1/residents/:id/search`
  over the transcripts' words, the library's documents, the bookmarks
  and the scenes, each scope ranked by its own half and `everything`
  interleaved from them. Results are typed and carry what the client
  opens. The halves are the systems' (`Kumbukumbu.search_words/4`,
  `search_bookmarks/3`, `surfaced/5`; `Seshat.search_within/5`); this
  controller bounds the query, keeps the parties' switches and shapes
  the answer.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["search"])

  plug(:witnessed)

  @scopes ~w(everything records bookmarks scenes words as-she-sees-it)
  # The interleaving's order, one of each a round.
  @everything [:records, :bookmarks, :scenes, :words]
  @page 50
  @min_chars 2
  @snippet 200

  # Scenes are searched by meaning in their days' files, `scenes/<day>.md`,
  # rendered from the scene rows on every write (seshat#52) and indexed
  # like any document; a chunk can hold several scenes, so `ref.id` stays
  # null and the day locates them (seshat#53).
  @scenes "scenes/"

  @result %Schema{
    type: :object,
    required: [:type, :ref, :title, :snippet, :at, :score],
    properties: %{
      type: %Schema{type: :string, enum: ["transcript", "document", "bookmark", "scene"]},
      ref: %Schema{
        type: :object,
        description:
          "What the client opens: a transcript's `session_key`, `turn_ref` and message `cursor`; a document's `path`; a bookmark's `number`; a scene's `day`, `id` (null until scenes are rows) and `path`"
      },
      title: %Schema{type: :string},
      snippet: %Schema{type: :string},
      at: %Schema{type: :string, format: :"date-time", nullable: true},
      score: %Schema{
        type: :number,
        nullable: true,
        description:
          "The scope's own measure, comparable within a scope only: similarity for documents and scenes, the ranked index's score for what she would see, where the match fell for bookmarks; null where the scope is unweighted (words, newest first)"
      }
    }
  }

  operation(:search,
    summary:
      "One search across kinds (kumbukumbu#59): `scope` one of everything, records, bookmarks, scenes, words or as-she-sees-it (default everything); at most 50 typed results, ranked within the scope and interleaved for everything; `q` at least 2 characters. Never a private, unshared session's words",
    parameters: [
      id: [in: :path, type: :string],
      q: [in: :query, type: :string, required: true],
      scope: [in: :query, type: %Schema{type: :string, enum: @scopes}]
    ],
    responses: [
      ok:
        {"the results", "application/json",
         %Schema{
           type: :object,
           required: [:q, :scope, :results],
           properties: %{
             q: %Schema{type: :string},
             scope: %Schema{type: :string, enum: @scopes},
             results: %Schema{type: :array, items: @result}
           }
         }},
      unprocessable_entity: "q shorter than 2 characters, or a scope not listed",
      forbidden: "the scope reads bookmarks and the agreement switches the witness's reads off"
    ]
  )

  def search(conn, %{"id" => id} = params) do
    q = String.trim(to_string(params["q"] || ""))
    scope = params["scope"] || "everything"

    with :ok <- check(conn, id, q, scope),
         {:ok, results} <- run(conn, id, q, scope) do
      json(conn, %{q: q, scope: scope, results: results})
    else
      %Plug.Conn{} = refused -> refused
      {:error, %{kind: _} = e} -> error(conn, 502, e)
    end
  end

  # The declared refusals, in order: the query's length, the scope's
  # name, and the witness's reads switch for the scopes that read
  # bookmarks.
  defp check(conn, id, q, scope) do
    cond do
      String.length(q) < @min_chars ->
        problem(
          conn,
          422,
          :query_too_short,
          :web_search_query_too_short,
          "q is at least #{@min_chars} characters"
        )

      scope not in @scopes ->
        problem(
          conn,
          422,
          :scope_unknown,
          :web_search_scope_unknown,
          "scope is one of #{Enum.join(@scopes, ", ")}"
        )

      scope in ["bookmarks", "as-she-sees-it"] and not reads?(id) ->
        problem(
          conn,
          403,
          :switched_off,
          :web_search_switched_off,
          "the witness's reads of the journal and bookmarks are switched off in the agreement; a version that turns them on, agreed by both, brings this scope back"
        )

      true ->
        :ok
    end
  end

  # ---- the scopes ----

  defp run(conn, id, q, "everything") do
    reads? = reads?(id)
    wanted = if reads?, do: @everything, else: @everything -- [:bookmarks]

    with {:ok, library} <- library(conn, id, q, wanted, reads?) do
      lists =
        Enum.map(wanted, fn
          :records -> library.records
          :scenes -> library.scenes
          :bookmarks -> bookmarks(id, q)
          :words -> words(conn, id, q)
        end)

      {:ok, lists |> interleave() |> Enum.take(@page)}
    end
  end

  defp run(conn, id, q, "records") do
    with {:ok, library} <- library(conn, id, q, [:records], reads?(id)),
         do: {:ok, library.records}
  end

  defp run(conn, id, q, "scenes") do
    with {:ok, library} <- library(conn, id, q, [:scenes], true), do: {:ok, library.scenes}
  end

  defp run(_conn, id, q, "bookmarks"), do: {:ok, bookmarks(id, q)}
  defp run(conn, id, q, "words"), do: {:ok, words(conn, id, q)}

  defp run(conn, id, q, "as-she-sees-it") do
    ranked? = AgathosDaimon.switch_on?(id, "ranked_memory")

    {:ok,
     id
     |> Kumbukumbu.surfaced(q, actor(conn), ranked?, @page)
     |> Enum.map(&bookmark(&1.bookmark, &1.score, q))}
  end

  # Records and scenes in one embedding of the query. Records are every
  # indexed document but the scenes, and the journal's days too while
  # the agreement keeps the witness from reading the journal.
  defp library(conn, id, q, wanted, reads?) do
    except = if reads?, do: [@scenes], else: [@scenes, "journal/"]

    filters =
      Enum.flat_map(wanted, fn
        :records -> [records: {:except, except}]
        :scenes -> [scenes: {:prefix, @scenes}]
        _other -> []
      end)

    with {:ok, hits} <- Seshat.search_within(id, q, actor(conn), filters, @page) do
      {:ok,
       %{
         records: Enum.map(Map.get(hits, :records, []), &document/1),
         scenes: Enum.map(Map.get(hits, :scenes, []), &scene/1)
       }}
    end
  end

  defp bookmarks(id, q),
    do:
      id |> Kumbukumbu.search_bookmarks(q, @page) |> Enum.map(&bookmark(&1.bookmark, &1.score, q))

  defp words(%{assigns: %{principal: p}}, id, q),
    do:
      {:account, p.account_id}
      |> Kumbukumbu.search_words(id, q, @page)
      |> Enum.map(&transcript(&1, q))

  # Round robin, in the scopes' order: each scope's first, then each
  # one's second. Scores are the scopes' own and never compared across.
  defp interleave(lists) do
    case Enum.reject(lists, &(&1 == [])) do
      [] -> []
      lists -> Enum.map(lists, &hd/1) ++ interleave(Enum.map(lists, &tl/1))
    end
  end

  defp reads?(id), do: AgathosDaimon.switch_on?(id, "witness_reads")

  # ---- shapes ----

  defp transcript({m, session}, q),
    do: %{
      type: "transcript",
      ref: %{
        session_key: m.session_key,
        turn_ref: m.turn_ref,
        cursor: "#{m.sequence}:#{m.position}"
      },
      title: Kumbukumbu.Conversation.title(session),
      snippet: around(m.content, q),
      at: m.sent_at,
      score: nil
    }

  defp document(hit),
    do: %{
      type: "document",
      ref: %{path: hit.path},
      title: hit.title || hit.path,
      snippet: clip(hit.text),
      at: hit.written_at,
      score: similarity(hit.distance)
    }

  defp scene(hit) do
    day = hit.path |> Path.basename(".md") |> String.slice(0, 10)

    %{
      type: "scene",
      ref: %{day: day, id: nil, path: hit.path},
      title: heading(hit.text) || hit.title || day,
      snippet: clip(hit.text),
      at: nil,
      score: similarity(hit.distance)
    }
  end

  defp bookmark(b, score, q),
    do: %{
      type: "bookmark",
      ref: %{number: b.number},
      title: b.line,
      snippet: bookmark_snippet(b, q),
      at: b.anchor_at,
      score: score && Float.round(score / 1, 3)
    }

  defp bookmark_snippet(b, q) do
    summary = b.summary || ""

    if String.contains?(String.downcase(summary), String.downcase(q)),
      do: around(summary, q),
      else: clip(if summary == "", do: b.line, else: summary)
  end

  defp similarity(distance) when is_number(distance), do: Float.round(1 - distance, 3)
  defp similarity(_distance), do: nil

  # The scene's own heading in the chunk, when the chunk holds one.
  defp heading(text) do
    case Regex.run(~r/^#+\s+(.+)$/m, text || "") do
      [_line, title] -> String.trim(title)
      _none -> nil
    end
  end

  # A window of the text around the first match, case aside.
  defp around(text, q) do
    text = text || ""

    case Regex.run(~r/#{Regex.escape(q)}/iu, text, return: :index) do
      [{at, _len}] ->
        start = max(String.length(binary_part(text, 0, at)) - div(@snippet, 4), 0)
        lead = if start > 0, do: "…", else: ""
        clip(lead <> String.slice(text, start, @snippet * 2))

      _none ->
        clip(text)
    end
  end

  defp clip(nil), do: ""

  defp clip(text) do
    text = text |> String.replace(~r/\s+/u, " ") |> String.trim()
    if String.length(text) > @snippet, do: String.slice(text, 0, @snippet) <> "…", else: text
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
            :agathos_daimon_web_search_not_witnessed
          )
        )
        |> halt()
  end
end
