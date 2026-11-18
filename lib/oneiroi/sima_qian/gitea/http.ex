defmodule Oneiroi.SimaQian.Gitea.HTTP do
  @moduledoc """
  Gitea's API behind the repositories' port (sima-qian#55), under the
  admin token: organizations, repositories, users and read grants, each
  made only when missing, so every call is safe to repeat. Pushes go over
  HTTPS with the token as the password (`Git.credentialed/2` keeps it out
  of the command line and off the disk past the call).
  """
  @behaviour Oneiroi.SimaQian.Gitea

  alias Oneiroi.Config.Secret
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.GiteaQueue

  @impl true
  def ensure_org(inst, org) do
    exists(get(inst, "/orgs/#{org}"), fn ->
      post(inst, "/orgs", %{
        username: org,
        visibility: "private",
        repo_admin_change_team_access: false
      })
    end)
  end

  @impl true
  def settled(inst, org, repo), do: settled(inst, org, repo, 30)

  defp settled(_inst, org, repo, 0),
    do:
      {:error,
       Error.new(:sima_qian_gitea_failed, :sima_qian_gitea_never_settled, repo: "#{org}/#{repo}")}

  defp settled(inst, org, repo, tries) do
    case request_body(inst, :get, "/repos/#{org}/#{repo}") do
      {:ok, 200, %{"empty" => false}} ->
        :ok

      _not_yet ->
        Process.sleep(1_000)
        settled(inst, org, repo, tries - 1)
    end
  end

  @impl true
  def ensure_repo(inst, org, repo) do
    exists(get(inst, "/repos/#{org}/#{repo}"), fn ->
      post(inst, "/orgs/#{org}/repos", %{
        name: repo,
        private: true,
        auto_init: false,
        default_branch: "main"
      })
    end)
  end

  # A rule on main (sima-qian#64): Gitea refuses a force-push or a
  # deletion of a protected branch, and lets those who write push.
  @impl true
  def protect(inst, org, repo) do
    exists(get(inst, "/repos/#{org}/#{repo}/branch_protections/main"), fn ->
      post(inst, "/repos/#{org}/#{repo}/branch_protections", %{
        branch_name: "main",
        rule_name: "main",
        enable_push: true
      })
    end)
  end

  @impl true
  def ensure_user(inst, login, email) do
    exists(get(inst, "/users/#{login}"), fn ->
      post(inst, "/admin/users", %{
        username: login,
        email: email,
        # Nobody's until the witness sets one (`Gitea.set_password/3`).
        password: Base.url_encode64(:crypto.strong_rand_bytes(24)),
        must_change_password: false,
        visibility: "private"
      })
    end)
  end

  @impl true
  def grant_read(inst, org, repo, login),
    do:
      done(
        request(inst, :put, "/repos/#{org}/#{repo}/collaborators/#{login}", %{permission: "read"})
      )

  @impl true
  def set_password(inst, login, password),
    do:
      done(
        request(inst, :patch, "/admin/users/#{login}", %{
          login_name: login,
          source_id: 0,
          password: password,
          must_change_password: false
        })
      )

  @impl true
  def remote(inst, org, repo) do
    with {:ok, %{url: url, token: token}} <- GiteaQueue.endpoint(inst) do
      uri = URI.parse(url)

      {:ok,
       Secret.wrap(
         URI.to_string(%{
           uri
           | userinfo: "oneiroi:" <> (token || ""),
             path: "/#{org}/#{repo}.git"
         })
       )}
    end
  end

  defp exists({:ok, 200}, _make), do: :ok
  defp exists({:ok, 404}, make), do: done(make.())
  defp exists(other, _make), do: done(other)

  defp done({:ok, status}) when status in 200..299, do: :ok

  defp done({:ok, status}),
    do: {:error, Error.new(:sima_qian_gitea_failed, :sima_qian_gitea_refused, status: status)}

  defp done({:error, _} = failed), do: failed

  defp get(inst, path), do: request(inst, :get, path, nil)
  defp post(inst, path, body), do: request(inst, :post, path, body)

  defp request(inst, method, path, body) do
    with {:ok, status, _body} <- request_body(inst, method, path, body), do: {:ok, status}
  end

  defp request_body(inst, method, path, body \\ nil) do
    with {:ok, %{url: url, token: token}} <- GiteaQueue.endpoint(inst),
         do: send_request(url, token, method, path, body)
  end

  defp send_request(url, token, method, path, body) do
    # A repository server, not a model provider: the repositories' port
    # (sima-qian#55), registered in the externals with its fake.
    # oneiroi:allow model_port
    case Req.request(
           method: method,
           url: url <> "/api/v1" <> path,
           json: body,
           headers: [{"authorization", "token " <> (token || "")}],
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, status, body}

      {:error, exception} ->
        {:error, Error.caught(:sima_qian_gitea_failed, :sima_qian_gitea_transport, exception)}
    end
  end
end
