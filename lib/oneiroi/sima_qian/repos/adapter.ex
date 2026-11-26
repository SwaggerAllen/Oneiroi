defmodule Oneiroi.SimaQian.Repos.Adapter do
  @moduledoc """
  What an adapter of the repositories' port answers (sima-qian#57):
  `Repos.Gitea` and `Repos.Local`. Its own module so an adapter depends
  on the contract and never on the port that chooses it.
  """

  alias Oneiroi.SimaQian.Repos

  @callback read(Repos.repo(), String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  @callback tree(Repos.repo()) :: {:ok, [%{path: String.t(), sha: String.t()}]} | {:error, term()}
  @callback write(Repos.repo(), [Repos.change()], String.t(), Repos.author()) ::
              {:ok, String.t() | :nothing} | {:error, term()}
  @callback log(Repos.repo(), String.t() | nil, pos_integer()) ::
              {:ok, [map()]} | {:error, term()}
  @callback history(Repos.repo(), String.t(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  @callback blob(Repos.repo(), String.t()) :: {:ok, binary()} | {:error, term()}
  # The commit `main` is at, nil before the first (sima-qian#61).
  @callback head(Repos.repo()) :: {:ok, String.t() | nil} | {:error, term()}
  # The tree as it stood at a commit, full or short: `sima_qian_repos_absent`
  # for one the repository never had.
  @callback tree_at(Repos.repo(), String.t()) ::
              {:ok, [%{path: String.t(), sha: String.t()}]} | {:error, term()}

  # The repository gone (sima-qian#70): only a succession's discarded fork
  # copy is ever deleted, and `Repos.delete/1` refuses anything else.
  @callback delete(Repos.repo()) :: :ok | {:error, term()}
end
