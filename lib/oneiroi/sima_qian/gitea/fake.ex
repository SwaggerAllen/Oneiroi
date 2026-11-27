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
  def protect(_inst, org, repo), do: put(:protected, "#{org}/#{repo}")

  @impl true
  # Gitea's fork: the parent's bare repository cloned whole.
  # sobelow_skip ["Traversal.FileModule"]
  def fork(_inst, from_org, from_repo, org, repo) do
    target = bare(org, repo)
    File.mkdir_p!(Path.dirname(target))

    # Through the git port, the one caller of an external binary.
    with {:ok, _} <-
           Git.run(Git.binary(), Path.dirname(target), [
             "clone",
             "-q",
             "--bare",
             bare(from_org, from_repo),
             target
           ]),
         do: put(:repos, "#{org}/#{repo}")
  end

  @impl true
  def delete_org(_inst, _org), do: :ok

  @impl true
  def grant_read(_inst, org, repo, login), do: put(:grants, {"#{org}/#{repo}", login})

  @impl true
  def set_password(_inst, login, password), do: put(:passwords, {login, password})

  @impl true
  def remote(_inst, org, repo), do: {:ok, bare(org, repo)}

  @impl true
  def settled(_inst, _org, _repo), do: :ok

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
