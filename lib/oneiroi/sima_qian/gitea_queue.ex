defmodule Oneiroi.SimaQian.GiteaQueue do
  @moduledoc """
  Asking for a repository to reach Gitea (sima-qian#56), apart from the
  sending: the household's commit and the resident's backup call this,
  and the sending (`Oneiroi.SimaQian.Gitea`) reads their repositories, so
  keeping the two apart keeps the calls one way.
  """

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  @worker :"Elixir.Oneiroi.SimaQian.GiteaWorker"

  @doc "Whether the server is set up here: a token to send with."
  @spec configured?() :: boolean()
  def configured?, do: token() != nil

  @doc "The admin token, or nil."
  def token do
    case Config.fetch!(:sima_qian, :gitea_token) do
      nil ->
        nil

      secret ->
        case Secret.unwrap(secret) do
          v when is_binary(v) and v != "" -> v
          _empty -> nil
        end
    end
  end

  @doc "Asks for a repository to be sent: one job per repository while one waits, so a burst of writes is one push."
  def later(kind, id) when kind in [:household, :resident] do
    if configured?(),
      do: Jobs.enqueue(@worker, %{(Atom.to_string(kind) <> "_id") => id}, schedule_in: 5),
      else: {:ok, :off}
  end
end
