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

  @scopes ~w(everything records bookmarks scenes words letters as-she-sees-it)
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
      scope: [in: :query, type: %Schema{type: :string, enum: @scopes}],
      page: [
        in: :query,
        type: :integer,
        description: "words only (kumbukumbu#67): the page, from 1, 50 a page"
      ],
      sort: [
        in: :query,
        type: %Schema{type: :string, enum: ["newest", "oldest"]},
        description: "words only: newest first (the default) or oldest"
      ],
      from: [
        in: :query,
        type: :string,
        description: "words only: an ISO 8601 instant; messages sent at or after it"
      ],
      to: [
        in: :query,
        type: :string,
        description: "words only: an ISO 8601 instant; messages sent before it"
      ]
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
             results: %Schema{type: :array, items: @result},
             page: %Schema{type: :integer, description: "words only"},
             more: %Schema{type: :boolean, description: "words only: another page follows"}
           }
         }},
      unprocessable_entity:
        "q shorter than 2 characters, a scope not listed, or a page, sort or range that does not read",
      forbidden: "the scope reads bookmarks and the agreement switches the witness's reads off"
    ]
  )

  def search(conn, %{"id" => id} = params) do
    q = String.trim(to_string(params["q"] || ""))
    scope = params["scope"] || "everything"

    with :ok <- check(conn, id, q, scope),
         {:ok, results} <- run(conn, id, q, scope, params) do
      json(conn, Map.merge(%{q: q, scope: scope}, results))
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

  # Words pages, sorts and takes a date range (kumbukumbu#67); every other
  # scope answers its one list.
  defp run(conn, id, q, "words", params) do
    case with(
           {:ok, opts, page} <- paging(params),
           {:ok, narrow} <- narrow("words", params),
           do: {:ok, opts ++ narrow, page}
         ) do
      {:ok, opts, page} ->
        %{assigns: %{principal: p}} = conn

        {rows, more} =
          Kumbukumbu.search_words_page(
            {:account, p.account_id},
            id,
            q,
            [witness: true, limit: @page, offset: (page - 1) * @page] ++ opts
          )

        {:ok, %{results: Enum.map(rows, &transcript(&1, q)), page: page, more: more}}

      {:refused, what} ->
        problem(conn, 422, :search_paging_invalid, :web_search_paging_invalid, what)
    end
  end

  # Records, bookmarks and scenes narrow and sort (kumbukumbu#69); the
  # results stay the scope's nearest or best 50, the sort orders them.
  defp run(conn, id, q, "letters", params) do
    with {:ok, narrow} <- narrow("letters", params),
         {:ok, sort} <- letter_sort(params["sort"]) do
      {:ok,
       %{
         results:
           id
           |> Kumbukumbu.search_letters(q, @page, [sort: sort] ++ narrow)
           |> Enum.map(&letter(&1, q))
       }}
    else
      {:refused, what} ->
        problem(conn, 422, :search_filter_invalid, :web_search_letters_filter_invalid, what)
    end
  end

  defp run(conn, id, q, scope, params) when scope in ["records", "bookmarks", "scenes"] do
    with {:ok, narrow} <- narrow(scope, params),
         {:ok, sort} <- sort_of(params["sort"]),
         {:ok, results} <- narrowed(conn, id, q, scope, narrow) do
      {:ok, %{results: sorted(results, sort)}}
    else
      {:refused, what} ->
        problem(conn, 422, :search_filter_invalid, :web_search_filter_invalid, what)

      other ->
        other
    end
  end

  defp run(conn, id, q, scope, _params) do
    with {:ok, results} <- run(conn, id, q, scope), do: {:ok, %{results: results}}
  end

  defp narrowed(conn, id, q, "records", narrow) do
    with {:ok, library} <- library(conn, id, q, [:records], reads?(id), narrow),
         do: {:ok, library.records}
  end

  defp narrowed(conn, id, q, "scenes", narrow) do
    with {:ok, library} <- library(conn, id, q, [:scenes], true, []),
         do: {:ok, scenes_kept(id, library.scenes, narrow)}
  end

  defp narrowed(_conn, id, q, "bookmarks", narrow) do
    {:ok,
     id
     |> Kumbukumbu.search_bookmarks(q, @page, narrow)
     |> Enum.map(&bookmark(&1.bookmark, &1.score, q))}
  end

  # A scene hit is a day's file: the day stays when it falls in the range
  # and one of its scenes has the mood and the person asked for.
  defp scenes_kept(_id, hits, []), do: hits

  defp scenes_kept(id, hits, narrow) do
    days = Enum.map(hits, & &1.ref.day)

    rows =
      case days do
        [] ->
          %{}

        days ->
          id |> Seshat.scenes(Enum.min(days), Enum.max(days)) |> Map.new(&{&1.day, &1.scenes})
      end

    Enum.filter(hits, fn %{ref: %{day: day}} ->
      in_range?(day, narrow) and scene_matches?(Map.get(rows, day, []), narrow)
    end)
  end

  defp in_range?(day, narrow) do
    from = narrow[:from] && narrow[:from] |> DateTime.to_date() |> Date.to_iso8601()
    to = narrow[:to] && narrow[:to] |> DateTime.to_date() |> Date.to_iso8601()
    (from == nil or day >= from) and (to == nil or day < to)
  end

  defp scene_matches?(scenes, narrow) do
    mood = narrow[:mood]
    person = narrow[:person]

    (mood == nil and person == nil) or
      Enum.any?(scenes, fn sc ->
        (mood == nil or String.contains?(String.downcase(sc.mood || ""), mood)) and
          (person == nil or Enum.any?(sc.people || [], &(String.downcase(&1) == person)))
      end)
  end

  # ---- the filters (kumbukumbu#69) ----

  @authors ~w(resident witness platform)
  @made_by ~w(resident witness)

  defp narrow(scope, params) do
    with {:ok, from} <- instant(params["from"], "from"),
         {:ok, to} <- instant(params["to"], "to"),
         {:ok, own} <- narrow_of(scope, params) do
      {:ok, Enum.reject([from: from, to: to] ++ own, &(elem(&1, 1) in [nil, []]))}
    end
  end

  defp narrow_of("words", params) do
    with {:ok, who} <- one_of(params["who"], @authors, "who"),
         {:ok, sent_to} <- one_of(params["sent_to"], @made_by, "sent_to"),
         {:ok, kinds} <-
           some_of(
             params["conversations"],
             Kumbukumbu.Conversation.kinds() ++ ["imported"],
             "conversations"
           ),
         do: {:ok, who: who, sent_to: sent_to, conversations: kinds}
  end

  defp narrow_of("records", params) do
    with {:ok, date} <- one_of(params["date"], ~w(created updated), "date"),
         {:ok, author} <- one_of(params["author"], @authors, "author"),
         do:
           {:ok,
            date: date && String.to_existing_atom(date),
            kinds: list(params["kinds"]),
            status: blank(params["status"]),
            author: author}
  end

  defp narrow_of("bookmarks", params) do
    with {:ok, made_by} <- one_of(params["made_by"], @made_by, "made_by"),
         do:
           {:ok,
            pinned: params["pinned"] == "true" || nil, tag: blank(params["tag"]), made_by: made_by}
  end

  defp narrow_of("letters", params),
    do: {:ok, written_by: blank(params["written_by"]), sent_to: blank(params["sent_to"])}

  defp narrow_of("scenes", params),
    do: {:ok, mood: lower(params["mood"]), person: lower(params["person"])}

  defp one_of(raw, allowed, name) do
    case blank(raw) do
      nil ->
        {:ok, nil}

      value ->
        if value in allowed,
          do: {:ok, value},
          else: {:refused, "#{name} is one of #{Enum.join(allowed, ", ")}"}
    end
  end

  defp some_of(raw, allowed, name) do
    values = list(raw)

    case values -- allowed do
      [] -> {:ok, values}
      _unknown -> {:refused, "#{name} are among #{Enum.join(allowed, ", ")}"}
    end
  end

  defp list(nil), do: []

  defp list(raw),
    do:
      raw
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  defp blank(nil), do: nil

  defp blank(raw),
    do: if(String.trim(to_string(raw)) == "", do: nil, else: String.trim(to_string(raw)))

  defp lower(raw), do: raw |> blank() |> then(&(&1 && String.downcase(&1)))

  defp letter_sort(nil), do: {:ok, :newest}
  defp letter_sort("newest"), do: {:ok, :newest}
  defp letter_sort("oldest"), do: {:ok, :oldest}
  defp letter_sort(_other), do: {:refused, "sort is newest or oldest"}

  defp sort_of(nil), do: {:ok, :relevance}
  defp sort_of("relevance"), do: {:ok, :relevance}
  defp sort_of("newest"), do: {:ok, :newest}
  defp sort_of("oldest"), do: {:ok, :oldest}
  defp sort_of(_other), do: {:refused, "sort is relevance, newest or oldest"}

  # A result without an instant (a scene read from its file) sorts by its day.
  defp sorted(results, :relevance), do: results
  defp sorted(results, :newest), do: Enum.sort_by(results, &instant_key/1, :desc)
  defp sorted(results, :oldest), do: Enum.sort_by(results, &instant_key/1, :asc)

  defp instant_key(%{at: %DateTime{} = at}), do: DateTime.to_iso8601(at)
  defp instant_key(%{ref: %{day: day}}) when is_binary(day), do: day
  defp instant_key(_result), do: ""

  defp paging(params) do
    with {:ok, page} <- page(params["page"]),
         {:ok, sort} <- sort(params["sort"]),
         {:ok, from} <- instant(params["from"], "from"),
         {:ok, to} <- instant(params["to"], "to") do
      {:ok, [sort: sort, from: from, to: to], page}
    end
  end

  defp page(nil), do: {:ok, 1}

  defp page(raw) do
    case Integer.parse(to_string(raw)) do
      {n, ""} when n >= 1 -> {:ok, n}
      _other -> {:refused, "page is a whole number from 1"}
    end
  end

  defp sort(nil), do: {:ok, :newest}
  defp sort("newest"), do: {:ok, :newest}
  defp sort("oldest"), do: {:ok, :oldest}
  defp sort(_other), do: {:refused, "sort is newest or oldest"}

  defp instant(nil, _name), do: {:ok, nil}
  defp instant("", _name), do: {:ok, nil}

  defp instant(raw, name) do
    case DateTime.from_iso8601(to_string(raw)) do
      {:ok, at, _offset} -> {:ok, at}
      _other -> {:refused, "#{name} is an ISO 8601 instant with its offset"}
    end
  end

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
  defp library(conn, id, q, wanted, reads?, narrow \\ []) do
    except = if reads?, do: [@scenes], else: [@scenes, "journal/"]
    date = Keyword.get(narrow, :date, :updated)

    filters =
      Enum.flat_map(wanted, fn
        :records -> [records: {:narrow, {:except, except}, narrow}]
        :scenes -> [scenes: {:prefix, @scenes}]
        _other -> []
      end)

    with {:ok, hits} <- Seshat.search_within(id, q, actor(conn), filters, @page) do
      {:ok,
       %{
         records: Enum.map(Map.get(hits, :records, []), &document(&1, date)),
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

  # `at` is the date the reader filtered on: the last write, or with
  # `date=created` the registration (kumbukumbu#69).
  defp document(hit, date),
    do: %{
      type: "document",
      ref: %{path: hit.path},
      title: hit.title || hit.path,
      snippet: clip(hit.text),
      at: if(date == :created, do: Map.get(hit, :registered_at), else: hit.written_at),
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

  defp letter(l, q),
    do: %{
      type: "letter",
      ref: %{number: l.number},
      title: "##{l.number} · #{l.from_name} → #{l.to_name}",
      snippet: around(l.text || "", q),
      at: l.sent_at,
      score: nil
    }

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
