defmodule Oneiroi.SimaQian.Repos.Local do
  @moduledoc """
  The repositories' port on disk (sima-qian#57): a git repository per
  resident and per household under the records root, read at `HEAD` (what
  is committed, never what lies in the working tree), written one commit
  at a time under a lock per repository, each change held to the same
  condition Gitea's API holds it to. The test suite's adapter, and a
  self-hoster's without Gitea.
  """
  @behaviour Oneiroi.SimaQian.Repos

  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git

  @impl true
  def read(repo, path) do
    dir = dir(repo)

    with true <- made?(dir) || :absent,
         {:ok, sha} <- Git.run("git", dir, ["rev-parse", "-q", "--verify", "HEAD:" <> path]),
         {:ok, bytes} <- Git.blob(dir, String.trim(sha)) do
      {:ok, bytes, String.trim(sha)}
    else
      _absent ->
        {:error,
         Error.new(:sima_qian_repos_absent, :sima_qian_repos_local_read_absent, path: path)}
    end
  end

  @impl true
  def tree(repo) do
    dir = dir(repo)

    if made?(dir) do
      with {:ok, entries} <- Git.tree(dir, "HEAD"),
           do: {:ok, for(%{type: "blob"} = e <- entries, do: %{path: e.path, sha: e.blob})}
    else
      {:ok, []}
    end
  end

  @impl true
  # Every path is under the records root, in a repository named by an id
  # the platform minted; the paths come from the library's own layout.
  # sobelow_skip ["Traversal.FileModule"]
  def write(repo, changes, message, author) do
    dir = dir(repo)
    :ok = Git.ensure_repo(dir)

    :global.trans({{__MODULE__, dir}, self()}, fn ->
      with {:ok, head} <- shas(repo),
           :ok <- conditions(changes, head) do
        Enum.each(changes, &apply_change(dir, &1))
        Git.commit_as(dir, Enum.map(changes, &elem(&1, 1)), message, author)
      end
    end)
  end

  @impl true
  def log(repo, path, limit) do
    dir = dir(repo)
    if made?(dir), do: Git.log(dir, path, limit), else: {:ok, []}
  end

  @impl true
  def history(repo, path, limit) do
    dir = dir(repo)
    if made?(dir), do: Git.history(dir, path, limit), else: {:ok, []}
  end

  @impl true
  def blob(repo, sha), do: Git.blob(dir(repo), sha)

  @doc "The repository's directory under the records root, as the backup and the household name it."
  def dir({:resident, id}), do: Path.join(root(), id)
  def dir({:household, id}), do: Path.join([root(), "households", id])

  defp root, do: Config.fetch!(:sima_qian, :root)

  # A repository made and committed to; one not made yet is empty, and
  # git is never started in a directory that is not there.
  defp made?(dir), do: File.dir?(Path.join(dir, ".git")) and Git.head?(dir)

  defp shas(repo) do
    with {:ok, files} <- tree(repo), do: {:ok, Map.new(files, &{&1.path, &1.sha})}
  end

  defp conditions(changes, head) do
    if Enum.all?(changes, &holds?(&1, head)),
      do: :ok,
      else: {:error, Error.new(:sima_qian_repos_conflict, :sima_qian_repos_local_condition)}
  end

  defp holds?({:create, path, _content}, head), do: not Map.has_key?(head, path)
  defp holds?({:put, _path, _content, :any}, _head), do: true
  defp holds?({:put, path, _content, base}, head), do: Map.get(head, path) == base
  defp holds?({:delete, path, :any}, head), do: Map.has_key?(head, path)
  defp holds?({:delete, path, base}, head), do: Map.get(head, path) == base

  # sobelow_skip ["Traversal.FileModule"]
  defp apply_change(dir, {:delete, path, _base}), do: File.rm(Path.join(dir, path))

  # sobelow_skip ["Traversal.FileModule"]
  defp apply_change(dir, change) do
    {path, content} =
      case change do
        {:create, path, content} -> {path, content}
        {:put, path, content, _base} -> {path, content}
      end

    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
  end
end
