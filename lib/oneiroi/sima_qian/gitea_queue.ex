defmodule Oneiroi.SimaQian.GiteaQueue do
  @moduledoc """
  Whether Gitea is set up here, its token, and where each instance
  answers (sima-qian#55, #60): apart from
  `Oneiroi.SimaQian.Gitea`, so the port's adapter and the sending can
  both read it without calling each other.
  """

  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.SimaQian.Error

  @primary "primary"

  @doc "The instance a household with no routing of its own is on (sima-qian#60)."
  def primary, do: @primary

  @doc """
  Where an instance answers (sima-qian#60): its URL and admin token. One
  instance today, `primary`, set by SIMA_QIAN_GITEA_URL and
  SIMA_QIAN_GITEA_TOKEN; a household routed to a name this build does
  not know is refused, never sent to the wrong server.
  """
  def endpoint(@primary),
    do: {:ok, %{url: Config.fetch!(:sima_qian, :gitea_url), token: token()}}

  def endpoint(other),
    do:
      {:error,
       Error.new(:sima_qian_gitea_unrouted, :sima_qian_gitea_instance_unknown, instance: other)}

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

  @moving {__MODULE__, :moving}

  @doc "Whether the records disk is being moved to Gitea (sima-qian#58), so writes wait for it."
  @spec moving?() :: boolean()
  def moving?, do: :persistent_term.get(@moving, false)

  @doc "Marks the move under way, or over."
  def moving(true), do: :persistent_term.put(@moving, true)
  def moving(false), do: :persistent_term.erase(@moving)
end
