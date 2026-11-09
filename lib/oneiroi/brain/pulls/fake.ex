defmodule Oneiroi.Brain.Pulls.Fake do
  @moduledoc """
  The in-memory pull requests port (conventions §9): a pull request,
  its files and its checks, set by a test; the token each read was
  handed is kept, so a test can say whose it was.
  """
  @behaviour Oneiroi.Brain.Pulls

  alias Oneiroi.Brain.Error
  alias Oneiroi.Config.Secret

  @key {__MODULE__, :pulls}
  @tokens {__MODULE__, :tokens}

  @doc "Sets pull request `number`: its row, its files (with patches) and its check runs."
  def put(number, pull, files, checks \\ []),
    do:
      :persistent_term.put(
        @key,
        Map.put(all(), number, %{pull: pull, files: files, checks: checks})
      )

  @doc "The tokens the reads were handed, in order, unwrapped (nil for anonymous)."
  def tokens, do: :persistent_term.get(@tokens, [])

  @doc "Forgets every pull request and every token seen."
  def clear do
    :persistent_term.erase(@key)
    :persistent_term.erase(@tokens)
    :ok
  end

  @impl true
  def pull(_repo, number, token) do
    seen(token)
    with_pull(number, & &1.pull)
  end

  @impl true
  def files(_repo, number, token) do
    seen(token)
    with_pull(number, & &1.files)
  end

  @impl true
  def checks(_repo, sha, token) do
    seen(token)

    case Enum.find(Map.values(all()), &(get_in(&1.pull, ["head", "sha"]) == sha)) do
      nil -> {:ok, []}
      p -> {:ok, p.checks}
    end
  end

  defp seen(nil), do: :persistent_term.put(@tokens, tokens() ++ [nil])
  defp seen(token), do: :persistent_term.put(@tokens, tokens() ++ [Secret.unwrap(token)])

  defp with_pull(number, take) do
    case Map.get(all(), number) do
      nil -> {:error, Error.new(:brain_pulls_absent, :brain_pulls_fake_not_found)}
      p -> {:ok, take.(p)}
    end
  end

  defp all, do: :persistent_term.get(@key, %{})
end
