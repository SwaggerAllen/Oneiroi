defmodule Oneiroi.Seshat.Citations do
  @moduledoc """
  Citations (spec §3.3, §6.5, F26): `<resident-slug>:<kind>/<id-or-path>`
  in a document's text, minted as edges by the index from the kinds the
  registry says cite, and resolved when read, never when indexed. A
  reference that does not resolve is kept and says why; a reference to
  another resident's slug is kept unresolved, since sharing between
  residents is what the slug prefix is for and is not built.

  The parsing and the frontmatter are pure here; the resolving reads
  the other systems' exports under the resident, and `figure/` goes
  through the figures port (`Oneiroi.Seshat.Figures`).
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos
  alias Oneiroi.Eunomia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian
  alias Oneiroi.Sunna

  @kinds ~w(bookmark position prediction date figure transcript writing design research journal wiki posts)
  # A ref ends on a letter, digit or `#`-less anchor character, so the full
  # stop closing a sentence stays with the sentence.
  @citation ~r/(?<![\w\/:])([a-z][a-z0-9-]*):(#{Enum.join(@kinds, "|")})\/([A-Za-z0-9](?:[A-Za-z0-9_.\/#:-]*[A-Za-z0-9])?)/

  # ---- parsing, pure ----

  @doc "Every citation in a text, in order of first appearance, each once: slug, kind, ref and the target as written."
  @spec extract(String.t()) :: [map()]
  def extract(text) when is_binary(text) do
    @citation
    |> Regex.scan(text)
    |> Enum.map(fn [_whole, slug, kind, ref] ->
      %{slug: slug, kind: kind, ref: ref, target: "#{slug}:#{kind}/#{ref}"}
    end)
    |> Enum.uniq_by(& &1.target)
    |> Enum.with_index(1)
    |> Enum.map(fn {c, i} -> Map.put(c, :ordinal, i) end)
  end

  @doc "The text with every citation removed: the copy for publishing (F25)."
  @spec strip(String.t()) :: String.t()
  def strip(text) when is_binary(text) do
    text
    |> then(
      &Regex.replace(~r/\s*\(([^()]*)\)/, &1, fn whole, inner ->
        strip_parenthetical(whole, inner)
      end)
    )
    |> String.replace(@citation, "")
    |> String.replace(~r/[ \t]+([,.;:!?])/, "\\1")
    |> String.replace(~r/[ \t]{2,}/, " ")
  end

  # A parenthetical that is citations and the words around them ("see",
  # "and", commas) goes whole; one with words of its own keeps them.
  defp strip_parenthetical(whole, inner) do
    cond do
      not Regex.match?(@citation, inner) ->
        whole

      Regex.match?(
        ~r/\A[\s,;]*(?:(?:see|cf\.?|and|also|the)\s*[,;]?\s*)*\z/i,
        String.replace(inner, @citation, "")
      ) ->
        ""

      true ->
        whole
    end
  end

  @doc "The frontmatter (`key: value` lines between `---` fences) and the body."
  @spec frontmatter(String.t()) :: {map(), String.t()}
  def frontmatter(text) when is_binary(text) do
    case Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n?(.*)\z/s, text) do
      [_whole, block, body] -> {parse_block(block), body}
      nil -> {%{}, text}
    end
  end

  @doc "The text with the given frontmatter keys set, the fences added when there were none."
  @spec with_frontmatter(String.t(), map()) :: String.t()
  def with_frontmatter(text, fields) when is_map(fields) do
    {front, body} = frontmatter(text)
    merged = Map.merge(front, fields)

    lines =
      merged
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{v}" end)

    "---\n" <> lines <> "\n---\n" <> body
  end

  @doc "The title: the frontmatter's, else the first heading, else the file's name."
  @spec title(String.t(), String.t()) :: String.t()
  def title(path, text) do
    {front, body} = frontmatter(text)

    cond do
      is_binary(front["title"]) and front["title"] != "" ->
        front["title"]

      heading = Regex.run(~r/^#\s+(.+)$/m, body) ->
        heading |> List.last() |> String.trim()

      true ->
        path |> Path.basename() |> Path.rootname()
    end
  end

  @doc "A writing piece's status from its frontmatter, `draft` when none; nil for a kind without one."
  @spec status(map(), String.t()) :: String.t() | nil
  def status(%{has_status: true}, text) do
    {front, _body} = frontmatter(text)
    front["status"] || "draft"
  end

  def status(_kind, _text), do: nil

  defp parse_block(block) do
    block
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/\A([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)\z/, line) do
        [_whole, key, value] -> Map.put(acc, key, String.trim(value))
        nil -> acc
      end
    end)
  end

  # ---- reading ----

  @doc "A document's references, each resolved now and the row marked."
  def references(resident_id, path) do
    rows = Scope.resident(resident_id, fn -> Store.references(path) end)
    resolve_rows(resident_id, rows)
  end

  @doc "The documents citing a target, resolved the same way."
  def cited_by(resident_id, target) when is_binary(target) do
    rows = Scope.resident(resident_id, fn -> Store.cited_by(target) end)
    resolve_rows(resident_id, rows)
  end

  @doc """
  References that resolved once and do not now: every reference with a
  `resolved_at` is resolved again on this read, since resolution is the
  read's and nobody reads a piece whose target quietly went. One resolve
  per such reference, nightly from the audit (huginn-muninn #15).
  """
  def drift(resident_id) do
    rows = Scope.resident(resident_id, fn -> Store.once_resolved() end)
    resident_id |> resolve_rows(rows) |> Enum.reject(& &1.resolved)
  end

  @doc "The review copy: content, status, and the references resolved (F25)."
  def review(resident_id, path) do
    with {:ok, path} <- Kinds.normalize(path) |> path_error(path),
         {:ok, row} <- registered(resident_id, path),
         {:ok, content} <- read(resident_id, path) do
      references = references(resident_id, path)
      footnotes = Enum.map_join(references, "\n", &footnote/1)
      rendered = if footnotes == "", do: content, else: content <> "\n\n---\n" <> footnotes

      {:ok,
       %{
         path: path,
         kind: row.kind,
         status: row.status,
         title: row.title,
         published_url: row.published_url,
         content: content,
         rendered: rendered,
         references: references
       }}
    end
  end

  defp footnote(%{resolved: true} = r), do: "[#{r.ordinal}] #{r.target}: #{r.label}"
  defp footnote(r), do: "[#{r.ordinal}] #{r.target}: unresolved, #{r.reason}"

  @doc "The copy for publishing: frontmatter and citations stripped."
  def publish_copy(resident_id, path) do
    with {:ok, path} <- Kinds.normalize(path) |> path_error(path),
         {:ok, _row} <- registered(resident_id, path),
         {:ok, content} <- read(resident_id, path) do
      {_front, body} = frontmatter(content)
      {:ok, strip(body)}
    end
  end

  # ---- resolving ----

  @doc "Resolves one citation for the resident now: `{:ok, label}` or `{:unresolved, reason}`."
  def resolve(%{id: resident_id, slug: slug}, %{slug: cited, kind: kind, ref: ref}) do
    if cited == slug,
      do: resolve_kind(resident_id, kind, ref),
      else:
        {:unresolved,
         "cites #{cited}, another resident; sharing between residents is not resolvable yet"}
  end

  defp resolve_kind(resident_id, "bookmark", ref) do
    with {:ok, number} <- integer(ref),
         {:ok, b, _span} <- Kumbukumbu.bookmark(resident_id, number) do
      {:ok, b.line}
    else
      _other -> {:unresolved, "no bookmark #{ref}"}
    end
  end

  defp resolve_kind(resident_id, "habit", ref) do
    with {:ok, number} <- integer(ref),
         %{} = h <- Enum.find(Ethos.habits(resident_id), &(&1.number == number)) do
      {:ok, "#{h.name} (#{h.stance})"}
    else
      _other -> {:unresolved, "no habit #{ref}"}
    end
  end

  defp resolve_kind(resident_id, "seed", ref) do
    with {:ok, number} <- integer(ref),
         %{} = s <- Enum.find(Ethos.seeds(resident_id), &(&1.number == number)) do
      {:ok, "#{s.text} (#{s.state})"}
    else
      _other -> {:unresolved, "no seed #{ref}"}
    end
  end

  defp resolve_kind(resident_id, "position", ref) do
    with {:ok, number} <- integer(ref),
         %{} = p <- Enum.find(Eunomia.positions(resident_id), &(&1.number == number)) do
      if p.replaced_by,
        do: {:ok, "#{p.statement} (replaced by position #{p.replaced_by})"},
        else: {:ok, p.statement}
    else
      _other -> {:unresolved, "no position #{ref}"}
    end
  end

  defp resolve_kind(resident_id, "prediction", ref) do
    %{open: open, resolved: resolved} = Eunomia.predictions(resident_id)

    with {:ok, number} <- integer(ref),
         %{} = p <- Enum.find(open ++ resolved, &(&1.number == number)) do
      {:ok, p.statement}
    else
      _other -> {:unresolved, "no prediction #{ref}"}
    end
  end

  defp resolve_kind(resident_id, "date", ref) do
    with {:ok, number} <- integer(ref),
         %{} = d <- Enum.find(Sunna.today(resident_id).dates, &(&1.number == number)) do
      {:ok, d.title}
    else
      _other -> {:unresolved, "no date #{ref}"}
    end
  end

  defp resolve_kind(resident_id, "figure", ref) do
    case Config.fetch!(:seshat, :figures).figure(resident_id, ref) do
      nil -> {:unresolved, "no figure #{ref}"}
      f -> {:ok, "#{f.label}: #{f.value}"}
    end
  end

  defp resolve_kind(resident_id, "transcript", ref) do
    key = ref |> String.split("#") |> hd()

    case Kumbukumbu.transcript({:resident, resident_id}, key) do
      {:ok, session, _messages} -> {:ok, "session #{session.kind} #{key}"}
      _other -> {:unresolved, "no session #{key}"}
    end
  end

  defp resolve_kind(resident_id, kind, ref) do
    path = document_path(kind, ref)

    case Scope.resident(resident_id, fn -> Store.document(path) end) do
      nil ->
        {:unresolved, "no document #{path}"}

      %{missing_at: at} when not is_nil(at) ->
        {:unresolved, "#{path} is missing from the repository"}

      row ->
        {:ok, row.title || path}
    end
  end

  # `writing/the-bake-off` is `writing/the-bake-off.md`; a ref with an
  # extension is the path itself.
  defp document_path(kind, ref) do
    ref = ref |> String.split("#") |> hd()
    if Path.extname(ref) == "", do: "#{kind}/#{ref}.md", else: "#{kind}/#{ref}"
  end

  defp resolve_rows(_resident_id, []), do: []

  defp resolve_rows(resident_id, rows) do
    {:ok, resident} = AgathosDaimon.fetch(resident_id)
    now = Clock.now()

    marked =
      Enum.map(rows, fn r ->
        {resolved?, label, reason} =
          case resolve(resident, %{slug: r.slug, kind: r.kind, ref: r.ref}) do
            {:ok, label} -> {true, label, nil}
            {:unresolved, reason} -> {false, nil, reason}
          end

        %{r | resolved: resolved?, label: label, reason: reason, checked_at: now}
      end)

    Scope.resident(resident_id, fn ->
      Enum.each(marked, fn r ->
        Store.mark_reference(r.from_path, r.ordinal, r.resolved, r.label, r.reason, now)
      end)
    end)

    Enum.map(marked, &shape/1)
  end

  defp shape(r) do
    %{
      from_path: r.from_path,
      ordinal: r.ordinal,
      target: r.target,
      kind: r.kind,
      ref: r.ref,
      resolved: r.resolved,
      label: r.label,
      reason: r.reason,
      resolved_at: r.resolved_at,
      checked_at: r.checked_at
    }
  end

  defp integer(ref) do
    case Integer.parse(ref) do
      {n, ""} -> {:ok, n}
      _other -> :error
    end
  end

  defp path_error({:ok, path}, _given), do: {:ok, path}

  defp path_error({:error, :path_invalid}, given),
    do: {:error, Error.new(:seshat_path_invalid, path: inspect(given))}

  defp registered(resident_id, path) do
    case Scope.resident(resident_id, fn -> Store.document(path) end) do
      nil -> {:error, Error.new(:seshat_no_such_document, path: path)}
      row -> {:ok, row}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read(resident_id, path) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      case File.read(Path.join(dir, path)) do
        {:ok, content} -> {:ok, content}
        {:error, _} -> {:error, Error.new(:seshat_no_such_file, path: path)}
      end
    end
  end
end
