defmodule Oneiroi.SimaQian.Repos.Local do
  @moduledoc """
  The repositories' port on disk (sima-qian#57): a directory per
  resident and per household under the records root, its files the
  repository's, each write committed to git there under its author.
  A file that appears in the directory by any other hand is read as
  Gitea reads a push from outside: part of the repository from then on.
  Each change is held to the same condition Gitea's API holds it to,
  against the file's blob as it stands, under a lock per repository.
  The test suite's adapter, development's, and a self-hoster's without
  Gitea.
  """
  @behaviour Oneiroi.SimaQian.Repos.Adapter

  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git

  @impl true
  # Every path is under the records root, in a repository named by an id
  # the platform minted; the paths come from the library's own layout.
  # sobelow_skip ["Traversal.FileModule"]
  def read(repo, path) do
    case File.read(Path.join(dir(repo), path)) do
      {:ok, bytes} ->
        {:ok, bytes, sha(bytes)}

      {:error, _absent} ->
        {:error,
         Error.new(:sima_qian_repos_absent, :sima_qian_repos_local_read_absent, path: path)}
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def tree(repo) do
    dir = dir(repo)

    {:ok,
     if File.dir?(dir) do
       for full <- Path.wildcard(Path.join(dir, "**"), match_dot: true),
           rel = Path.relative_to(full, dir),
           not String.starts_with?(rel, ".git/"),
           rel != ".git",
           File.regular?(full),
           do: %{path: rel, sha: sha(File.read!(full))}
     else
       []
     end}
  end

  @impl true
  def head(repo) do
    dir = dir(repo)
    {:ok, if(made?(dir), do: Git.head(dir))}
  end

  @impl true
  def tree_at(repo, commit) do
    dir = dir(repo)

    with true <- made?(dir),
         {:ok, entries} <- Git.tree(dir, commit) do
      {:ok, for(%{type: "blob", path: p, blob: b} <- entries, do: %{path: p, sha: b})}
    else
      _unknown ->
        {:error,
         Error.new(:sima_qian_repos_absent, :sima_qian_repos_local_commit_absent, commit: commit)}
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def write(repo, changes, message, author) do
    dir = dir(repo)
    :ok = Git.ensure_repo(dir)

    :global.trans({{__MODULE__, dir}, self()}, fn -> held(repo, dir, changes, message, author) end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp held(repo, dir, changes, message, author) do
    with :ok <- conditions(repo, changes) do
      # A removal git never tracked (a file only on disk) is no change
      # to stage; git would refuse its path.
      paths = for c <- changes, staged?(dir, c), do: elem(c, 1)
      Enum.each(changes, &apply_change(dir, &1))
      commit(dir, paths, message, author)
    end
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
  # A blob committed is in git; one only on disk is found by its sha.
  def blob(repo, sha) do
    dir = dir(repo)

    with {:error, _} <- committed_blob(dir, sha),
         {:ok, files} <- tree(repo),
         %{path: path} <- Enum.find(files, &(&1.sha == sha)),
         {:ok, bytes, _} <- read(repo, path) do
      {:ok, bytes}
    else
      {:ok, bytes} when is_binary(bytes) ->
        {:ok, bytes}

      _none ->
        {:error, Error.new(:sima_qian_repos_absent, :sima_qian_repos_local_blob_absent, sha: sha)}
    end
  end

  @doc "The repository's directory under the records root, as the backup and the household name it."
  @impl true
  # The directory is the records root (a setting) under a minted id.
  # sobelow_skip ["Traversal.FileModule"]
  def delete(repo) do
    File.rm_rf!(dir(repo))
    :ok
  end

  def dir({:resident, id}), do: Path.join(root(), id)
  def dir({:household, id}), do: Path.join([root(), "households", id])

  defp root, do: Config.fetch!(:sima_qian, :root)

  @doc "A git blob's sha for these bytes, as git and Gitea name it."
  def sha(bytes),
    do:
      :crypto.hash(:sha, ["blob ", Integer.to_string(byte_size(bytes)), <<0>>, bytes])
      |> Base.encode16(case: :lower)

  defp committed_blob(dir, sha) do
    if made?(dir),
      do: Git.blob(dir, sha),
      else: {:error, Error.new(:sima_qian_repos_absent, :sima_qian_repos_local_unmade, sha: sha)}
  end

  defp staged?(dir, {:delete, path, _base}),
    do: match?({:ok, out} when out != "", Git.run("git", dir, ["ls-files", "--", path]))

  defp staged?(_dir, _change), do: true

  defp commit(_dir, [], _message, _author), do: {:ok, :nothing}
  defp commit(dir, paths, message, author), do: Git.commit_as(dir, paths, message, author)

  defp made?(dir), do: File.dir?(Path.join(dir, ".git")) and Git.head?(dir)

  defp conditions(repo, changes) do
    if Enum.all?(changes, &holds?(repo, &1)),
      do: :ok,
      else: {:error, Error.new(:sima_qian_repos_conflict, :sima_qian_repos_local_condition)}
  end

  defp holds?(repo, {:create, path, _content}), do: current(repo, path) == nil
  defp holds?(_repo, {:put, _path, _content, :any}), do: true
  defp holds?(repo, {:put, path, _content, base}), do: current(repo, path) == base
  defp holds?(repo, {:delete, path, :any}), do: current(repo, path) != nil
  defp holds?(repo, {:delete, path, base}), do: current(repo, path) == base

  defp current(repo, path) do
    case read(repo, path) do
      {:ok, _bytes, sha} -> sha
      _absent -> nil
    end
  end

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
