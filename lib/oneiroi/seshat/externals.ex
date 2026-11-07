defmodule Oneiroi.Seshat.Externals do
  @moduledoc """
  External sources (seshat#46): web pages and repositories' documents,
  commissioned for citing by either party, fetched by the reader on the
  witness's machine when either asks and never on a clock, and kept
  whole in the library as the latest copy, with its URL, the instant it
  was fetched and the digest of its words. A fresh copy is asked for by
  name; when it lands the conversation that asked is told whether it
  differs from the copy before, and the repository's history keeps
  every copy.

  Two kinds, each a citation kind of its own:

  - `web`: a page, `<slug>:web/<key>#<anchor>`, its key the first 16 hex
    of the SHA-256 of its URL without the fragment;
  - `doc`: a file in a repository, `<slug>:doc/github/<owner>/<repo>/<path>#<slug>`,
    given by its GitHub URL (`blob/<ref>/<path>`, or raw), fetched at the
    commit its ref names at the time, which the copy records.

  An anchor is a heading's slug or id; failing those, the nearest
  heading that holds its words, said so; failing that, the passage that
  holds its words. The copy's words are other people's: never an edge,
  never an instruction.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.ExternalCopy
  alias Oneiroi.Seshat.Router
  alias Oneiroi.Seshat.Store

  @github ~r{\Ahttps://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/blob/([^/\s]+)/([^\s#?]+)}
  @raw ~r{\Ahttps://raw\.githubusercontent\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/([^/\s]+)/([^\s#?]+)}
  @url ~r/\Ahttps?:\/\/[^\s]+\z/

  # ---- the locator, pure ----

  @doc """
  What a URL names: `{:ok, %{kind, key, url, ref}}`. A GitHub file (its
  page or its raw URL) is a `doc` keyed `github/<owner>/<repo>/<path>`
  at its ref; any other http(s) URL is a `web` page keyed by its digest.
  """
  @spec locate(String.t()) :: {:ok, map()} | :error
  def locate(url) when is_binary(url) do
    url = url |> String.trim() |> String.split("#") |> hd()

    cond do
      String.length(url) > 2_048 or not Regex.match?(@url, url) -> :error
      m = Regex.run(@github, url) -> doc(m)
      m = Regex.run(@raw, url) -> doc(m)
      true -> {:ok, %{kind: "web", key: web_key(url), url: url, ref: nil}}
    end
  end

  def locate(_other), do: :error

  defp doc([_whole, owner, repo, ref, path]) do
    path = URI.decode(path)

    {:ok,
     %{
       kind: "doc",
       key: "github/#{owner}/#{repo}/#{path}",
       url: "https://github.com/#{owner}/#{repo}/blob/#{ref}/#{path}",
       ref: ref
     }}
  end

  @doc "A web page's key: the first 16 hex of the SHA-256 of its URL."
  @spec web_key(String.t()) :: String.t()
  def web_key(url),
    do: :sha256 |> :crypto.hash(url) |> Base.encode16(case: :lower) |> binary_part(0, 16)

  @doc "Where a source's copy is kept in the library."
  @spec copy_path(map()) :: String.t()
  def copy_path(%{kind: "web", key: key}), do: "external/web/#{key}.md"

  def copy_path(%{kind: "doc", key: key}),
    do:
      if(String.ends_with?(key, ".md"), do: "external/doc/#{key}", else: "external/doc/#{key}.md")

  @doc "A source's citation, for the resident's slug."
  @spec citation(String.t(), map()) :: String.t()
  def citation(slug, x), do: "#{slug}:#{x.kind}/#{x.key}"

  # ---- commissioning and fetching ----

  @doc """
  Commissions the source a URL names and asks the reader for its first
  copy; `{:ok, number, :new | :known}`. A source already commissioned is
  answered with its number, and nothing is asked again.
  """
  def commission(resident_id, session_key, url, %Actor{} = actor) do
    with {:ok, x} <- locate(url) |> located(),
         {:ok, events} <-
           dispatch(%Commands.CommissionExternal{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             kind: x.kind,
             key: x.key,
             url: x.url,
             ref: x.ref,
             session_key: session_key
           }) do
      row = Scope.resident(resident_id, fn -> Store.external_by_key(x.key) end)
      {:ok, row.number, if(events == [], do: :known, else: :new)}
    end
  end

  @doc "Asks the reader for a fresh copy of source `number`; `:ok`, or `:waiting` when one is already asked."
  def ask_fetch(resident_id, session_key, number, %Actor{} = actor) do
    with {:ok, events} <-
           dispatch(%Commands.AskExternalFetch{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             session_key: session_key
           }) do
      if events == [], do: {:ok, :waiting}, else: {:ok, :asked}
    end
  end

  @doc """
  Keeps the copy the reader brought of source `number`
  (`%{text, title, commit}`): written whole under external/ with its
  provenance, recorded, and the conversation that asked told whether it
  differs from the copy before. The path.
  """
  def fetched(resident_id, number, %{} = copy, %Actor{} = actor) do
    text = to_string(field(copy, :text) || "")
    title = copy |> field(:title) |> to_string() |> String.trim() |> String.slice(0, 300)

    with %Store.External{status: "asked"} = row <- external(resident_id, number) || absent(number),
         :ok <- copy_ok(text),
         digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, text), case: :lower),
         commit = commit(field(copy, :commit)),
         path = copy_path(row),
         now = Clock.now(),
         {:ok, _} <-
           Documents.write(
             resident_id,
             path,
             document(row, title, text, digest, commit, now),
             actor,
             core: true
           ),
         {:ok, _} <-
           dispatch(%Commands.RecordExternalFetch{
             actor: actor,
             at: now,
             id: resident_id,
             number: number,
             path: path,
             title: if(title == "", do: row.url, else: title),
             content_hash: digest,
             commit: commit,
             bytes: byte_size(text)
           }) do
      tell(resident_id, row, fetched_line(row, path, digest))
      {:ok, path}
    else
      %Store.External{} -> {:ok, :not_asked}
      other -> other
    end
  end

  @doc "Records that the reader could not fetch source `number`, and tells the conversation that asked."
  def fail(resident_id, number, reason, %Actor{} = actor) do
    reason = reason |> to_string() |> String.slice(0, 2_000)

    with {:ok, events} <-
           dispatch(%Commands.FailExternalFetch{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             number: number,
             reason: reason
           }) do
      if events != [],
        do: tell(resident_id, external(resident_id, number), "could not be fetched: #{reason}")

      :ok
    end
  end

  @doc "The external sources, newest first; `status:` narrows."
  def externals(resident_id, opts \\ []),
    do: Scope.resident(resident_id, fn -> Store.externals(opts) end)

  @doc "One external source by number, or nil."
  def external(resident_id, number) when is_integer(number),
    do: Scope.resident(resident_id, fn -> Store.external(number) end)

  def external(_resident_id, _number), do: nil

  @doc "One external source by its citation's kind and ref, or nil (`ExternalCopy.by_citation/3`)."
  defdelegate by_citation(resident_id, kind, ref), to: ExternalCopy

  # ---- reading ----

  @doc "The copy of a cited source, whole or the section an anchor names (`ExternalCopy.read/3`)."
  defdelegate read(resident_id, kind, ref), to: ExternalCopy

  # ---- helpers ----

  defp document(row, title, text, digest, commit, at) do
    commit_line = if commit, do: "commit: #{commit}\n", else: ""
    ref_line = if row.ref, do: "ref: #{row.ref}\n", else: ""

    "---\nsource: #{row.url}\nkind: #{row.kind}\nkey: #{row.key}\n#{ref_line}#{commit_line}" <>
      "fetched_at: #{DateTime.to_iso8601(at)}\ncontent_hash: #{digest}\ntitle: #{inspect(title)}\n" <>
      "---\n\n" <> text
  end

  defp fetched_line(row, path, digest) do
    cond do
      is_nil(row.content_hash) ->
        "the first copy is kept at #{path}."

      row.content_hash == digest ->
        "a fresh copy, the same words as the copy of #{iso(row.fetched_at)}."

      true ->
        "a fresh copy at #{path}; its words differ from the copy of #{iso(row.fetched_at)}, which the repository's history keeps."
    end
  end

  defp iso(nil), do: "before"
  defp iso(at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp copy_ok(text) do
    bound = Oneiroi.Config.fetch!(:seshat, :document_bytes) - 4_096

    if String.trim(text) != "" and byte_size(text) <= bound and String.valid?(text),
      do: :ok,
      else:
        {:error,
         Error.new(:seshat_external_copy_invalid, :seshat_externals_copy_invalid, bound: bound)}
  end

  defp commit(c) when is_binary(c) do
    if Regex.match?(~r/\A[0-9a-f]{7,64}\z/, c), do: c, else: nil
  end

  defp commit(_other), do: nil

  defp located({:ok, x}), do: {:ok, x}

  defp located(:error),
    do: {:error, Error.new(:seshat_external_invalid, :seshat_externals_locate_invalid)}

  # The conversation that asked is told by a house letter, as research's
  # is; a fetch asked from no conversation tells nobody.
  defp tell(_resident_id, nil, _what), do: :ok
  defp tell(_resident_id, %{session_key: nil}, _what), do: :ok

  defp tell(resident_id, row, what) do
    _ =
      Kumbukumbu.letter_to_session(
        resident_id,
        row.session_key,
        "The reader, on external source ##{row.number} (#{row.url}): #{what}",
        Actor.platform()
      )

    :ok
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp absent(what),
    do:
      {:error,
       Error.new(:seshat_no_such_external, :seshat_externals_absent, what: to_string(what))}

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_externals_dispatch_failed, reason)}
    end
  end
end
