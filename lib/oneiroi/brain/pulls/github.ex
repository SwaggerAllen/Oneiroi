defmodule Oneiroi.Brain.Pulls.GitHub do
  @moduledoc """
  The pull requests port on GitHub's REST API (brain#71): reads only,
  with `BRAIN_GITHUB_TOKEN` when set (a higher rate limit; the platform's
  repository is public, so none is needed).
  """
  @behaviour Oneiroi.Brain.Pulls

  alias Oneiroi.Brain.Error
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  @api "https://api.github.com"
  @per_page 100
  @max_pages 30

  @impl true
  def pull(repo, number), do: get("/repos/#{repo}/pulls/#{number}", [])

  @impl true
  def files(repo, number), do: pages("/repos/#{repo}/pulls/#{number}/files", 1, [])

  @impl true
  def checks(repo, sha) do
    with {:ok, %{"check_runs" => runs}} <-
           get("/repos/#{repo}/commits/#{sha}/check-runs", per_page: @per_page),
         do: {:ok, runs}
  end

  defp pages(path, page, acc) do
    case get(path, per_page: @per_page, page: page) do
      {:ok, batch} when is_list(batch) and length(batch) == @per_page and page < @max_pages ->
        pages(path, page + 1, acc ++ batch)

      {:ok, batch} when is_list(batch) ->
        {:ok, acc ++ batch}

      {:error, _} = failed ->
        failed
    end
  end

  defp get(path, params) do
    case Req.get(@api <> path,
           params: params,
           headers: headers(),
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, Error.new(:brain_pulls_absent, :brain_pulls_github_not_found)}

      {:ok, %{status: status}} ->
        {:error, Error.new(:brain_pulls_failed, :brain_pulls_github_status, status: status)}

      {:error, exception} ->
        {:error, Error.caught(:brain_pulls_failed, :brain_pulls_github_transport, exception)}
    end
  end

  defp headers do
    base = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "oneiroi"}
    ]

    case Config.fetch!(:brain, :github_token) do
      nil -> base
      token -> [{"authorization", "Bearer " <> Secret.unwrap(token)} | base]
    end
  end
end
