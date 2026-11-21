defmodule Oneiroi.SimaQian.RemoteCheck.Fake do
  @moduledoc """
  The in-memory remote check (conventions §9): a test says what a
  repository is with `put/2`; one it never named is absent.
  """
  @behaviour Oneiroi.SimaQian.RemoteCheck

  alias Oneiroi.SimaQian.Error

  @key {__MODULE__, :repos}

  @doc "Says what `owner/repo` is: `%{private: boolean, push: boolean | nil}`, or `:not_found`."
  def put(repo, answer),
    do: :persistent_term.put(@key, Map.put(:persistent_term.get(@key, %{}), repo, answer))

  @doc "Forgets every repository named."
  def clear, do: :persistent_term.put(@key, %{})

  @impl true
  def check(repo, _token) do
    case Map.get(:persistent_term.get(@key, %{}), repo, :not_found) do
      :not_found ->
        {:error, Error.new(:sima_qian_remote_absent, :sima_qian_remote_check_fake_not_found)}

      answer ->
        {:ok, answer}
    end
  end
end
