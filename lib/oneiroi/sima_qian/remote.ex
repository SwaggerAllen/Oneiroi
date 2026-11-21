defmodule Oneiroi.SimaQian.Remote do
  @moduledoc """
  A backup remote, checked (sima-qian#65; the witness, 2026-11-21: "we
  should add validation that we at least get a url in that field, if not
  that it actually accepts pushes", and of its visibility: "worth
  checking so we can warn the user").

  - **Its shape** is refused unless it is a remote: an `https://`,
    `http://`, `ssh://` or `git://` URL with a host and a path, an
    scp-style `user@host:path`, or a local path (the platform's own dry
    run and tests). An email address, a bare word, a host with no path
    are refused (`sima_qian_remote_invalid`).
  - **What it is**, asked of its host where the host answers (GitHub
    today, through `RemoteCheck`): `visibility` `private`, `public` or
    `unknown`, and `push` `yes`, `no` or `unknown`. A token that cannot
    push is refused at set (`sima_qian_remote_unpushable`); a public
    repository is set and warned of, never refused, and the nightly
    backup asks again, so one made public later is warned of too. The
    check never stops a backup: until F80 encrypts what it carries, the
    warning is the guard.
  """

  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Error

  @url ~r{\A(https?|ssh|git)://[^/\s@]*@?[A-Za-z0-9.-]+(:\d+)?/[^\s]+\z}
  @scp ~r{\A[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^\s/][^\s]*\z}
  @github ~r{\A(?:https://(?:[^@/]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([^/\s]+)/([^/\s]+?)(?:\.git)?/?\z}

  @doc "`:ok` when `url` has a remote's shape, else the refusal."
  @spec shape(String.t()) :: :ok | {:error, Error.t()}
  def shape(url) when is_binary(url) do
    url = String.trim(url)

    if Regex.match?(@url, url) or Regex.match?(@scp, url) or local?(url),
      do: :ok,
      else: {:error, Error.new(:sima_qian_remote_invalid, :sima_qian_remote_not_a_remote)}
  end

  def shape(_url),
    do: {:error, Error.new(:sima_qian_remote_invalid, :sima_qian_remote_not_text)}

  @doc "Whether `url` is a local path, the platform's own: no host to ask."
  @spec local?(String.t()) :: boolean()
  def local?(url), do: String.starts_with?(url, ["/", "file://"])

  @doc """
  What the remote is, as its host says: `%{visibility, push}`, each a
  word (`private`/`public`/`unknown`, `yes`/`no`/`unknown`). A local
  path is the platform's own, `private`. Never raises; a host that
  cannot be asked is `unknown`.
  """
  @spec check(String.t(), term()) :: %{visibility: String.t(), push: String.t()}
  def check(url, token) do
    cond do
      local?(url) -> %{visibility: "private", push: "unknown"}
      repo = github(url) -> asked(client().check(repo, token), token)
      true -> %{visibility: "unknown", push: "unknown"}
    end
  end

  defp asked({:ok, %{private: private, push: push}}, _token),
    do: %{visibility: if(private, do: "private", else: "public"), push: word(push)}

  # Hidden from the token is no push; with no token, it may be private.
  defp asked({:error, %{kind: :sima_qian_remote_absent}}, token),
    do: %{visibility: "unknown", push: if(token, do: "no", else: "unknown")}

  defp asked({:error, _reason}, _token), do: %{visibility: "unknown", push: "unknown"}

  defp word(true), do: "yes"
  defp word(false), do: "no"
  defp word(_none), do: "unknown"

  defp github(url) do
    case Regex.run(@github, String.trim(url)) do
      [_, owner, repo] -> owner <> "/" <> repo
      _other -> nil
    end
  end

  defp client, do: Config.fetch!(:sima_qian, :remote_check_client)
end
