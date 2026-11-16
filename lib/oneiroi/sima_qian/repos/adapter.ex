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
end
