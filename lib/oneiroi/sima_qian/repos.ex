defmodule Oneiroi.SimaQian.Repos do
  @moduledoc """
  Every repository, read and written through one port (sima-qian#57; the
  witness, 2026-11-16: Gitea the source of truth, its API the only way
  in). A repository is a resident's (`{:resident, id}`) or a household's
  (`{:household, id}`).

  A write is one commit of several file changes under its author, each
  change carrying the condition it holds under, the compare-and-swap
  Gitea itself enforces:

  - `{:create, path, content}`: only if the path is absent (an append,
    such as a thread's reply, can never overwrite another's);
  - `{:put, path, content, base}`: only if the path's blob is still
    `base` (`nil` for absent), or whatever it is with `:any`;
  - `{:delete, path, base}`: likewise.

  A condition that no longer holds is `sima_qian_repos_conflict`, and the
  caller reads again and retries or refuses; nothing is half-written.
  Two adapters: `Repos.Gitea` in every real build, `Repos.Local` (a git
  repository on disk per repository, the same conditions) in test and
  for a self-hoster without Gitea.
  """

  @type repo :: {:resident, String.t()} | {:household, String.t()}
  @type change ::
          {:create, String.t(), iodata()}
          | {:put, String.t(), iodata(), String.t() | nil | :any}
          | {:delete, String.t(), String.t() | :any}
  @type author :: %{name: String.t(), email: String.t()}

  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Repos.Cache

  @platform %{name: "Oneiroi", email: "oneiroi@records.invalid"}

  @doc "The platform's own authorship, for what no member wrote."
  def platform, do: @platform

  @doc """
  Who a commit in a resident's repository is by (sima-qian#52, #57): the
  resident under her name, her witness as her witness, anything else the
  platform. Addresses are placeholders under the platform's name, never
  a person's own.
  """
  def author(%Oneiroi.Actor{kind: :resident, id: id}) do
    case Oneiroi.AgathosDaimon.fetch(id) do
      {:ok, r} -> %{name: r.name, email: "#{r.slug}@residents.oneiroi.invalid"}
      _gone -> @platform
    end
  end

  def author(%Oneiroi.Actor{kind: :witness, id: id}),
    do: %{name: "her witness", email: "#{id}@witnesses.oneiroi.invalid"}

  def author(_actor), do: @platform

  @doc "A file's bytes and its blob, or `sima_qian_repos_absent`."
  def read(repo, path), do: client().read(repo, path)

  @doc "A file's bytes, or nil when it is absent."
  def text(repo, path) do
    case read(repo, path) do
      {:ok, content, _sha} -> content
      _absent -> nil
    end
  end

  @doc "Whether a path holds a file."
  def exists?(repo, path), do: match?({:ok, _, _}, read(repo, path))

  @doc "Every file of the repository at its head: `%{path, sha}`."
  def tree(repo), do: client().tree(repo)

  @doc "The files under `prefix` (a folder, no trailing slash needed), at the head."
  def list(repo, prefix) do
    p = String.trim_trailing(prefix, "/") <> "/"

    with {:ok, files} <- tree(repo),
         do: {:ok, Enum.filter(files, &String.starts_with?(&1.path, p))}
  end

  @doc "One commit of `changes` under `author`; `sima_qian_repos_conflict` when a condition no longer holds."
  def write(_repo, [], _message, _author), do: {:ok, :nothing}
  def write(repo, changes, message, author), do: client().write(repo, changes, message, author)

  @doc "The repository's history, or a path's, newest first: `%{sha, at, author, subject}`."
  def log(repo, path, limit), do: client().log(repo, path, limit)

  @doc "The commits that changed `path`, newest first: `%{commit, at, subject, blob}`."
  def history(repo, path, limit), do: client().history(repo, path, limit)

  @doc "A blob's bytes by its sha, from the cache when it has them (a blob never changes)."
  def blob(repo, sha) do
    case Cache.get(sha) do
      nil ->
        with {:ok, bytes} <- client().blob(repo, sha) do
          Cache.put(sha, bytes)
          {:ok, bytes}
        end

      bytes ->
        {:ok, bytes}
    end
  end

  @doc "The repository at its head, `%{path => sha}`: one call, then `at/3` reads from it."
  def snapshot(repo) do
    with {:ok, files} <- tree(repo), do: {:ok, Map.new(files, &{&1.path, &1.sha})}
  end

  @doc "A file's bytes in a snapshot, through the cache; nil when the snapshot has no such file."
  def at(repo, snapshot, path) do
    case Map.get(snapshot, path) do
      nil ->
        nil

      sha ->
        case blob(repo, sha) do
          {:ok, bytes} -> bytes
          _failed -> nil
        end
    end
  end

  @doc "The paths in a snapshot under `prefix`, sorted."
  def under(snapshot, prefix) do
    p = String.trim_trailing(prefix, "/") <> "/"
    snapshot |> Map.keys() |> Enum.filter(&String.starts_with?(&1, p)) |> Enum.sort()
  end

  @doc """
  Runs `fun` with this process's repository reads and writes on the disk
  (`Repos.Local`), whatever the platform's adapter: an import assembles a
  resident's repository in a working directory of its own (the clone,
  the seeds, the library's adoption, the fresh history), then commits it
  and sends it to Gitea whole (sima-qian#57). Nothing else uses it.
  """
  def locally(fun) do
    previous = Process.put({__MODULE__, :local}, true)

    try do
      fun.()
    after
      if previous, do: :ok, else: Process.delete({__MODULE__, :local})
    end
  end

  @doc "Whether this process is assembling a repository on the disk (`locally/1`)."
  def local?,
    do: Process.get({__MODULE__, :local}) == true or client() == Oneiroi.SimaQian.Repos.Local

  defp client do
    if Process.get({__MODULE__, :local}) == true,
      do: Oneiroi.SimaQian.Repos.Local,
      else: Config.fetch!(:sima_qian, :repos_client)
  end
end
