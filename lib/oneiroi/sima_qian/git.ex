defmodule Oneiroi.SimaQian.Git do
  @moduledoc """
  The git port (spec §6.10): the one place the `git` binary is called.
  A provider is a remote URL: a local path for tests and self-hosters, or
  GitHub over HTTPS with a fine-grained token in the URL (plan decision
  5), held in an `Oneiroi.Config.Secret` from the request onward; `git`
  is told never to prompt, so a bad token fails rather than hangs.

  The token never reaches git's arguments (`credentialed/2`). On
  2026-11-01 production's git was missing, `System.cmd` raised, and the
  crash report printed its arguments: the clone URL with Lily's read
  token, into the service log. Arguments are what a crash report, `ps`
  and `/proc` all show, so git is given the URL without its userinfo
  and reads the credential from a file only this process can open.

  Gitea and any other remote by URL need nothing new: a URL is a URL.
  """

  alias Oneiroi.Config.Secret
  alias Oneiroi.SimaQian.Error

  @env [{"GIT_TERMINAL_PROMPT", "0"}]
  @identity ["-c", "user.name=Oneiroi", "-c", "user.email=oneiroi@records.invalid"]

  @doc "Makes `dir` a repository on `main` if it is not one."
  @spec ensure_repo(Path.t()) :: :ok | {:error, Error.t()}
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
  @spec init_bare(Path.t()) :: :ok | {:error, Error.t()}
  # sobelow_skip ["Traversal.FileModule"]
  def init_bare(path) do
    File.mkdir_p!(path)
    with {:ok, _} <- git(path, ["init", "-q", "--bare", "-b", "main"]), do: :ok
  end

  @doc "Stages `pathspecs` and commits them alone; `{:ok, :nothing}` when nothing changed."
  @spec commit(Path.t(), [String.t()], String.t()) ::
          {:ok, String.t() | :nothing} | {:error, Error.t()}
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

  @doc "Pushes `main` to `remote`."
  @spec push(Path.t(), String.t() | Secret.t()) :: :ok | {:error, Error.t()}
  def push(dir, remote) do
    credentialed(remote, fn url, config ->
      with {:ok, _} <- git(dir, config ++ ["push", "-q", url, "HEAD:refs/heads/main"]), do: :ok
    end)
  end

  @doc "Clones `remote` into `dir`, shallow enough to read the records and the last commit."
  @spec clone(String.t() | Secret.t(), Path.t()) :: :ok | {:error, Error.t()}
  def clone(remote, dir) do
    credentialed(remote, fn url, config ->
      with {:ok, _} <-
             git(Path.dirname(dir), config ++ ["clone", "-q", "--branch", "main", url, dir]),
           do: :ok
    end)
  end

  @doc """
  Calls `fun` with the remote as git is told it: the URL without its
  userinfo, and the `-c` arguments pointing git at a credential file
  holding what the userinfo said. A remote with no userinfo (a local
  path, a public URL) passes through with no arguments added.

  The file sits in a directory made for this call, readable by this
  user only, and is removed when `fun` returns or raises. It holds
  scheme, userinfo and host and nothing else: git's credential store
  matches a stored path against the request's, and a request carries no
  path unless `credential.useHttpPath` is set, so a stored URL with a
  path would never match. The empty `credential.helper` first clears any
  helper the machine's own git config names, so the token is offered to
  no other store.
  """
  @spec credentialed(String.t() | Secret.t(), (String.t(), [String.t()] -> result)) :: result
        when result: term()
  # sobelow_skip ["Traversal.FileModule"]
  def credentialed(remote, fun) do
    plain = if is_binary(remote), do: remote, else: Secret.unwrap(remote)
    uri = URI.parse(plain)

    case uri.userinfo do
      nil ->
        fun.(plain, [])

      _userinfo ->
        dir = Path.join(System.tmp_dir!(), "oneiroi-git-#{System.unique_integer([:positive])}")
        File.mkdir_p!(dir)
        File.chmod!(dir, 0o700)
        file = Path.join(dir, "credentials")

        File.write!(
          file,
          URI.to_string(%URI{
            scheme: uri.scheme,
            userinfo: uri.userinfo,
            host: uri.host,
            port: uri.port
          }) <> "\n"
        )

        File.chmod!(file, 0o600)

        try do
          fun.(URI.to_string(%{uri | userinfo: nil}), [
            "-c",
            "credential.helper=",
            "-c",
            "credential.helper=store --file=" <> file
          ])
        after
          File.rm_rf(dir)
        end
    end
  end

  @doc "Whether `dir` has a commit at `HEAD`."
  @spec head?(Path.t()) :: boolean()
  def head?(dir), do: match?({:ok, _}, git(dir, ["rev-parse", "--verify", "-q", "HEAD"]))

  @doc """
  The trailers on the history's first commit: where the repository began,
  which a head committed on top of someone else's history does not say.
  """
  @spec root_trailers(Path.t()) :: %{optional(String.t()) => String.t()}
  def root_trailers(dir) do
    with {:ok, roots} <- git(dir, ["rev-list", "--max-parents=0", "HEAD"]),
         [root | _] <- String.split(roots, "\n", trim: true),
         {:ok, out} <- git(dir, ["log", "-1", "--format=%(trailers:only,unfold)", root]) do
      out |> String.split("\n", trim: true) |> Enum.flat_map(&trailer/1) |> Map.new()
    else
      _ -> %{}
    end
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

  @doc "The remote as a record may name it: the URL without its userinfo, where a GitHub token rides."
  @spec public_url(String.t() | Secret.t()) :: String.t()
  def public_url(remote) do
    url = if is_binary(remote), do: remote, else: Secret.unwrap(remote)

    case URI.parse(url) do
      %URI{scheme: scheme} = uri when is_binary(scheme) -> URI.to_string(%{uri | userinfo: nil})
      _bare -> url
    end
  end

  @doc "The GitHub HTTPS URL carrying a fine-grained token, wrapped so nothing but git's credential file sees it."
  @spec github_url(String.t(), String.t()) :: Secret.t()
  def github_url(url, token) do
    uri = URI.parse(url)
    Secret.wrap(URI.to_string(%{uri | userinfo: "x-access-token:" <> token}))
  end

  @binary "git"

  @doc "The binary this port runs, which the runtime image must carry."
  @spec binary() :: String.t()
  def binary, do: @binary

  defp git(dir, args), do: run(@binary, dir, args)

  @doc false
  # The binary is an argument so a test can name one that is missing or
  # cannot run; every caller in this module passes `@binary`.
  #
  # A failure is `:sima_qian_git_failed` with git's output in `details`,
  # any token in a URL redacted, because git echoes the remote on
  # failure. A git that cannot start is `:sima_qian_git_unstarted`, an
  # error too and never a raise: `System.cmd` raises when the binary is
  # missing, and the crash report prints the call's arguments, which hold
  # the clone URL and its token. The production image shipped without git
  # on 2026-11-01, and the first real import put Lily's read token into
  # the service log that way, under a bare 500. Of that raise, the
  # binary's name and the reason's class are kept (`enoent` is a binary
  # that is missing); the exception's message is not, since it quotes
  # the call.
  #
  # Sobelow reads a variable binary as command injection. No request value
  # reaches it: this module passes `@binary`, and only the port's own test
  # names another.
  # sobelow_skip ["CI.System"]
  @spec run(String.t(), Path.t(), [String.t()]) :: {:ok, String.t()} | {:error, Error.t()}
  def run(binary, dir, args) do
    case System.cmd(binary, args, cd: dir, env: @env, stderr_to_stdout: true) do
      {out, 0} ->
        {:ok, out}

      {out, code} ->
        {:error,
         Error.new(:sima_qian_git_failed, :sima_qian_git_run_failed,
           output: redact(out),
           status: code
         )}
    end
  rescue
    e in ErlangError ->
      {:error,
       Error.caught(:sima_qian_git_unstarted, :sima_qian_git_run_unstarted, e,
         binary: binary,
         reason: Oneiroi.Error.describe(e.original)
       )}
  end

  defp redact(text), do: Regex.replace(~r|://[^@/\s]+@|, text, "://[redacted]@")
end
