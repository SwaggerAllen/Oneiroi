defmodule Oneiroi.Records.Git do
  @moduledoc """
  The git port (spec §6.10): the one place the `git` binary is called.
  A provider is a remote URL: a local path for tests and self-hosters, or
  GitHub over HTTPS with a fine-grained token in the URL (plan decision
  5), built in memory here and never logged; `git` is told never to
  prompt, so a bad token fails rather than hangs.

  Gitea and any other remote by URL need nothing new: a URL is a URL.
  """

  @env [{"GIT_TERMINAL_PROMPT", "0"}]
  @identity ["-c", "user.name=Oneiroi", "-c", "user.email=oneiroi@records.invalid"]

  @doc "Makes `dir` a repository on `main` if it is not one."
  @spec ensure_repo(Path.t()) :: :ok | {:error, String.t()}
  # Sobelow reads a `File` call on a built path as a traversal; every path
  # here is the records root (a setting) under a resident id the platform
  # minted, or a clone this code made under the temp dir. No request
  # value reaches a path in this system.
  # sobelow_skip ["Traversal.FileModule"]
  def ensure_repo(dir) do
    File.mkdir_p!(dir)

    if File.dir?(Path.join(dir, ".git")),
      do: :ok,
      else: with({:ok, _} <- git(dir, ["init", "-q", "-b", "main"]), do: :ok)
  end

  @doc "Makes a bare repository at `path`, for tests and local remotes."
  @spec init_bare(Path.t()) :: :ok | {:error, String.t()}
  # sobelow_skip ["Traversal.FileModule"]
  def init_bare(path) do
    File.mkdir_p!(path)
    with {:ok, _} <- git(path, ["init", "-q", "--bare", "-b", "main"]), do: :ok
  end

  @doc "Stages `pathspecs` and commits them alone; `{:ok, :nothing}` when nothing changed."
  @spec commit(Path.t(), [String.t()], String.t()) ::
          {:ok, String.t() | :nothing} | {:error, String.t()}
  def commit(dir, pathspecs, message) do
    with {:ok, _} <- git(dir, ["add", "-A", "--"] ++ pathspecs),
         {:ok, staged} <- git(dir, ["diff", "--cached", "--name-only", "--"] ++ pathspecs) do
      if String.trim(staged) == "",
        do: {:ok, :nothing},
        else: commit_staged(dir, pathspecs, message)
    end
  end

  defp commit_staged(dir, pathspecs, message) do
    with {:ok, _} <-
           git(dir, @identity ++ ["commit", "-q", "--only", "-m", message, "--"] ++ pathspecs),
         {:ok, sha} <- git(dir, ["rev-parse", "HEAD"]) do
      {:ok, String.trim(sha)}
    end
  end

  @doc "Paths changed or untracked outside `pathspecs`: what a backup refuses to commit."
  @spec stray(Path.t(), [String.t()]) :: [String.t()]
  def stray(dir, prefixes) do
    case git(dir, ["status", "--porcelain", "--untracked-files=all"]) do
      {:ok, out} ->
        out
        |> String.split("\n", trim: true)
        |> Enum.map(&String.slice(&1, 3..-1//1))
        |> Enum.reject(fn path -> Enum.any?(prefixes, &String.starts_with?(path, &1)) end)

      {:error, _} ->
        []
    end
  end

  @doc "Pushes `main` to `url`."
  @spec push(Path.t(), String.t()) :: :ok | {:error, String.t()}
  def push(dir, url) do
    with {:ok, _} <- git(dir, ["push", "-q", url, "HEAD:refs/heads/main"]), do: :ok
  end

  @doc "Clones `url` into `dir`, shallow enough to read the records and the last commit."
  @spec clone(String.t(), Path.t()) :: :ok | {:error, String.t()}
  def clone(url, dir) do
    with {:ok, _} <- git(Path.dirname(dir), ["clone", "-q", "--branch", "main", url, dir]),
         do: :ok
  end

  @doc "The trailers on `HEAD`'s message, as `%{\"Oneiroi-Root\" => ...}`."
  @spec head_trailers(Path.t()) :: %{optional(String.t()) => String.t()}
  def head_trailers(dir) do
    case git(dir, ["log", "-1", "--format=%(trailers:only,unfold)"]) do
      {:ok, out} ->
        out |> String.split("\n", trim: true) |> Enum.flat_map(&trailer/1) |> Map.new()

      {:error, _} ->
        %{}
    end
  end

  defp trailer(line) do
    case String.split(line, ":", parts: 2) do
      [key, value] -> [{String.trim(key), String.trim(value)}]
      _ -> []
    end
  end

  @doc "The GitHub HTTPS URL carrying a fine-grained token; built here, logged nowhere."
  @spec github_url(String.t(), String.t()) :: String.t()
  def github_url(url, token) do
    uri = URI.parse(url)
    URI.to_string(%{uri | userinfo: "x-access-token:" <> token})
  end

  # Errors carry git's stderr with any token in a URL redacted, because
  # git echoes the remote on failure.
  defp git(dir, args) do
    case System.cmd("git", args, cd: dir, env: @env, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _code} -> {:error, redact(out)}
    end
  end

  defp redact(text), do: Regex.replace(~r|://[^@/\s]+@|, text, "://[redacted]@")
end
