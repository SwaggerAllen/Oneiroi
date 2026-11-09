defmodule Oneiroi.Brain.Pulls.Fake do
  @moduledoc """
  The in-memory pull requests port (conventions §9): a pull request,
  its files and its checks, set by a test.
  """
  @behaviour Oneiroi.Brain.Pulls

  alias Oneiroi.Brain.Error

  @key {__MODULE__, :pulls}

  @doc "Sets pull request `number`: its row, its files (with patches) and its check runs."
  def put(number, pull, files, checks \\ []),
    do:
      :persistent_term.put(
        @key,
        Map.put(all(), number, %{pull: pull, files: files, checks: checks})
      )

  @doc "Forgets every pull request."
  def clear, do: :persistent_term.erase(@key)

  @impl true
  def pull(_repo, number), do: with_pull(number, & &1.pull)

  @impl true
  def files(_repo, number), do: with_pull(number, & &1.files)

  @impl true
  def checks(_repo, sha) do
    case Enum.find(Map.values(all()), &(get_in(&1.pull, ["head", "sha"]) == sha)) do
      nil -> {:ok, []}
      p -> {:ok, p.checks}
    end
  end

  defp with_pull(number, take) do
    case Map.get(all(), number) do
      nil -> {:error, Error.new(:brain_pulls_absent, :brain_pulls_fake_not_found)}
      p -> {:ok, take.(p)}
    end
  end

  defp all, do: :persistent_term.get(@key, %{})
end
