defmodule Oneiroi.Seshat.Documents do
  @moduledoc """
  The command edge for documents (spec §6.5, F25, F27): a write through
  the flow, the adoption of a file made outside it, the reads, a
  steward's publish and a piece's discussion. The file is the record,
  in the resident's repository where the backup commits it (sima-qian
  #14's classes already name every kind's folder); the event is its
  provenance; the index runs after every write and adoption so a search
  sees the file at once rather than tomorrow.

  Who writes: either party, through a document write, into a kind the
  registry marks `:resident`; the platform's kinds (mail, feeds,
  correspondence, the journal) are refused here and written by their
  systems. Publishing is the steward's (spec §10's Library screen).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Index
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Router
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian

  # Sobelow reads a `File` call on a built path as a traversal; every
  # path here is the repository root (sima-qian's setting under a
  # resident id the platform minted) joined with a path `Kinds.normalize/1`
  # accepted: plain segments under a registered folder, no `..`, no
  # leading slash. A request value reaches the filesystem only through
  # that check.
  # sobelow_skip ["Traversal.FileModule"]
  @doc "Writes a file through the flow (`core: true` for a kind the platform writes); returns the path, the kind, whether anything changed, and whether the index ran clean."
  def write(resident_id, path, content, %Actor{} = actor, opts \\ []) when is_binary(content) do
    with {:ok, path} <- normalize(path),
         {:ok, kind} <- writable_kind(path, Keyword.get(opts, :core, false)),
         :ok <- size_ok(content),
         {:ok, dir} <- SimaQian.repository_dir(resident_id),
         {:ok, events} <-
           dispatch(%Commands.WriteDocument{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             path: path,
             kind: kind.kind,
             hash: hash(content),
             bytes: byte_size(content)
           }) do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
      index = Index.run(resident_id, actor)

      {:ok,
       %{
         path: path,
         kind: kind.kind,
         changed: events != [],
         indexed: match?({:ok, _}, index)
       }}
    end
  end

  @doc "Adopts a file found in the repository under a kind's folder, as it is; the index runs."
  # sobelow_skip ["Traversal.FileModule"]
  def adopt(resident_id, path, %Actor{} = actor) do
    with {:ok, path} <- normalize(path),
         {:ok, dir} <- SimaQian.repository_dir(resident_id),
         {:ok, content} <- read_file(Path.join(dir, path)),
         kind = Kinds.kind_of(path),
         {:ok, events} <-
           dispatch(%Commands.AdoptDocument{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             path: path,
             kind: kind.kind,
             hash: hash(content),
             bytes: byte_size(content)
           }) do
      index = Index.run(resident_id, actor)

      {:ok,
       %{path: path, kind: kind.kind, adopted: events != [], indexed: match?({:ok, _}, index)}}
    end
  end

  @doc "Files under a kind's folder that no document registers, sorted; what the Library screen offers to adopt."
  # sobelow_skip ["Traversal.FileModule"]
  def unadopted(resident_id) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      registered = resident_id |> list() |> MapSet.new(& &1.path)

      Kinds.all()
      |> Enum.flat_map(fn kind -> files_under(dir, kind.folder) end)
      |> Enum.reject(&MapSet.member?(registered, &1))
      |> Enum.sort()
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp files_under(dir, folder) do
    root = Path.join(dir, folder)

    if File.dir?(root),
      do:
        root
        |> Path.join("**")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&Path.relative_to(&1, dir)),
      else: []
  end

  @doc "The registered documents, by kind then path."
  def list(resident_id), do: Scope.resident(resident_id, fn -> Store.documents() end)

  @doc "One document: its row and its content as on disk."
  # sobelow_skip ["Traversal.FileModule"]
  def fetch(resident_id, path) do
    with {:ok, path} <- normalize(path),
         {:ok, row} <- registered(resident_id, path),
         {:ok, dir} <- SimaQian.repository_dir(resident_id),
         {:ok, content} <- read_file(Path.join(dir, path)) do
      {:ok, %{document: row, content: content, discussions: discussions(resident_id, path)}}
    end
  end

  @doc "A steward publishes a piece at a URL: the event first, then the file's status set to published with it, which the index reads."
  def publish(resident_id, path, url, %Actor{kind: :steward} = actor) do
    with {:ok, path} <- normalize(path),
         {:ok, _} <-
           dispatch(%Commands.PublishPiece{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             path: path,
             url: url
           }),
         {:ok, %{content: content}} <- fetch(resident_id, path),
         {:ok, _} <-
           write(
             resident_id,
             path,
             Citations.with_frontmatter(content, %{"status" => "published", "published" => url}),
             actor
           ) do
      :ok
    end
  end

  def publish(_resident_id, _path, _url, %Actor{}),
    do: {:error, Error.new(:seshat_not_the_steward)}

  @doc "Links a session to a piece as its discussion."
  def discuss(resident_id, path, session_key, %Actor{} = actor) when is_binary(session_key) do
    with {:ok, path} <- normalize(path),
         {:ok, _} <-
           dispatch(%Commands.OpenDiscussion{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             path: path,
             session_key: session_key
           }) do
      :ok
    end
  end

  def discussions(resident_id, path),
    do: Scope.resident(resident_id, fn -> Store.discussions(path) end)

  # ---- helpers ----

  @doc "The SHA-256 of a file's bytes, hex, lower case: what decides a re-embed."
  @spec hash(binary()) :: String.t()
  def hash(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp normalize(path) do
    case Kinds.normalize(path) do
      {:ok, path} -> {:ok, path}
      {:error, :path_invalid} -> {:error, Error.new(:seshat_path_invalid, path: inspect(path))}
    end
  end

  defp writable_kind(path, core?) do
    kind = Kinds.kind_of(path)

    cond do
      kind.access != :resident and not core? ->
        {:error, Error.new(:seshat_kind_not_writable, kind: kind.kind)}

      not Kinds.text?(path) ->
        {:error, Error.new(:seshat_path_invalid, path: path)}

      true ->
        {:ok, kind}
    end
  end

  defp size_ok(content) do
    bound = Config.fetch!(:seshat, :document_bytes)

    if byte_size(content) <= bound,
      do: :ok,
      else: {:error, Error.new(:seshat_too_large, bytes: byte_size(content), bound: bound)}
  end

  defp registered(resident_id, path) do
    case Scope.resident(resident_id, fn -> Store.document(path) end) do
      nil -> {:error, Error.new(:seshat_no_such_document, path: path)}
      row -> {:ok, row}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_file(full) do
    case File.read(full) do
      {:ok, content} -> {:ok, content}
      {:error, _reason} -> {:error, Error.new(:seshat_no_such_file, path: full)}
    end
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :no_such_document} ->
        {:error, Error.new(:seshat_no_such_document, path: command.path)}

      {:error, :not_publishable} ->
        {:error, Error.new(:seshat_not_publishable, path: command.path)}

      {:error, :url_invalid} ->
        {:error, Error.new(:seshat_url_invalid)}

      {:error, other} ->
        {:error, other}
    end
  end
end
