defmodule Oneiroi.SimaQian.RemoteCheck.GitHub do
  @moduledoc """
  The remote check on GitHub's REST API (sima-qian#65): one read of the
  repository with the witness's token. `private` is GitHub's own field;
  `push` is the token's permission, nil when GitHub does not say (an
  anonymous read). A 404 is a repository absent or hidden from the token
  (`sima_qian_remote_absent`).
  """
  @behaviour Oneiroi.SimaQian.RemoteCheck

  alias Oneiroi.Config.Secret
  alias Oneiroi.SimaQian.Error

  @api "https://api.github.com"

  @impl true
  def check(repo, token) do
    case Req.get(@api <> "/repos/" <> repo,
           headers: headers(token),
           retry: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"private" => private} = body}} ->
        {:ok, %{private: private == true, push: get_in(body, ["permissions", "push"])}}

      {:ok, %{status: 404}} ->
        {:error, Error.new(:sima_qian_remote_absent, :sima_qian_remote_check_github_not_found)}

      {:ok, %{status: status}} ->
        {:error,
         Error.new(:sima_qian_remote_check_failed, :sima_qian_remote_check_github_status,
           status: status
         )}

      {:error, exception} ->
        {:error,
         Error.caught(
           :sima_qian_remote_check_failed,
           :sima_qian_remote_check_github_transport,
           exception
         )}
    end
  end

  defp headers(token) do
    base = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "oneiroi"}
    ]

    case token && Secret.reveal(token) do
      value when is_binary(value) and value != "" ->
        [{"authorization", "Bearer " <> value} | base]

      _none ->
        base
    end
  end
end
