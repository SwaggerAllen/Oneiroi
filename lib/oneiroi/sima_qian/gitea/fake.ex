defmodule Oneiroi.SimaQian.Gitea.Fake do
  @moduledoc """
  The in-memory repository server (conventions §9): every organization,
  repository, user, grant and password kept, and each repository a bare
  one on disk under the system's temporary directory, so a push really
  lands and a test can read what arrived.
  """
  @behaviour Oneiroi.SimaQian.Gitea

  alias Oneiroi.SimaQian.Git

  @key {__MODULE__, :state}

  @impl true
  def ensure_org(_inst, org), do: put(:orgs, org)

  @impl true
  def ensure_repo(_inst, org, repo) do
    :ok = Git.init_bare(bare(org, repo))
    put(:repos, "#{org}/#{repo}")
  end

  @impl true
  def ensure_user(_inst, login, _email), do: put(:users, login)

  @impl true
  def grant_read(_inst, org, repo, login), do: put(:grants, {"#{org}/#{repo}", login})

  @impl true
  def set_password(_inst, login, password), do: put(:passwords, {login, password})

  @impl true
  def remote(_inst, org, repo), do: {:ok, bare(org, repo)}

  @doc "The bare repository a push to `org/repo` lands in."
  def bare(org, repo),
    do: Path.join([System.tmp_dir!(), "oneiroi-gitea-fake", org, repo <> ".git"])

  @doc "What the fake holds: `:orgs`, `:repos`, `:users`, `:grants`, `:passwords`."
  def state, do: :persistent_term.get(@key, %{})

  @doc "Forgets it all, the bare repositories with it."
  # The fake's own directory under the system's temporary one; no
  # request value reaches the path.
  # sobelow_skip ["Traversal.FileModule"]
  def clear do
    File.rm_rf(Path.join(System.tmp_dir!(), "oneiroi-gitea-fake"))
    :persistent_term.erase(@key)
    :ok
  end

  defp put(set, value) do
    s = state()
    :persistent_term.put(@key, Map.put(s, set, Enum.uniq(Map.get(s, set, []) ++ [value])))
    :ok
  end
end
