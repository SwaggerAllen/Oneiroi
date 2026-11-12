defmodule Oneiroi.Brain.Pulls.GitHub do
  @moduledoc """
  The pull requests port on GitHub's REST API (brain#71): reads only,
  with the token it is handed (the witness's, gaia#24, else `BRAIN_GITHUB_TOKEN`) (a higher rate limit; the platform's
  repository is public, so none is needed).
  """
  @behaviour Oneiroi.Brain.Pulls

  alias Oneiroi.Brain.Error
  alias Oneiroi.Config.Secret

  @api "https://api.github.com"
  @per_page 100
  @max_pages 30

  @impl true
  def pull(repo, number, token), do: get("/repos/#{repo}/pulls/#{number}", [], token)

  @impl true
  def files(repo, number, token),
    do: pages("/repos/#{repo}/pulls/#{number}/files", 1, [], token)

  @impl true
  def checks(repo, sha, token) do
    with {:ok, %{"check_runs" => runs}} <-
           get("/repos/#{repo}/commits/#{sha}/check-runs", [per_page: @per_page], token),
         do: {:ok, runs}
  end

  defp pages(path, page, acc, token) do
    case get(path, [per_page: @per_page, page: page], token) do
      {:ok, batch} when is_list(batch) and length(batch) == @per_page and page < @max_pages ->
        pages(path, page + 1, acc ++ batch, token)

      {:ok, batch} when is_list(batch) ->
        {:ok, acc ++ batch}

      {:error, _} = failed ->
        failed
    end
  end

  defp get(path, params, token) do
    case Req.get(@api <> path,
           params: params,
           headers: headers(token),
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

  @doc false
  # Public for its test: an unset token reads anonymously (brain#85).
  def headers(token) do
    base = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"},
      {"user-agent", "oneiroi"}
    ]

    # An unset optional secret arrives wrapped around nothing: a read with
    # no token is an anonymous read, never a crash (brain#85).
    case token && Secret.unwrap(token) do
      value when is_binary(value) and value != "" ->
        [{"authorization", "Bearer " <> value} | base]

      _none ->
        base
    end
  end
end
