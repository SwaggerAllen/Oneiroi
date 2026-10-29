defmodule OneiroiWeb.Plugs.RequirePrincipal do
  @moduledoc """
  Halts with 401 when `OneiroiWeb.Plugs.Authenticate` found no principal.

  An adapter's token (spec §8) is a principal for four paths and nothing
  else: opening its session, reporting a turn, capturing one, reading
  the context. Everything under `/v1` beyond those is an account's, so
  an adapter's token there is refused here, before any controller reads
  an account off it. The list is explicit so the test can assert it.
  """
  @behaviour Plug

  import Plug.Conn

  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.Gaia.Error
  alias OneiroiWeb.Controllers.Helpers

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{assigns: %{principal: %AdapterPrincipal{}}} = conn, _opts) do
    if adapter_path?(conn.method, conn.path_info), do: conn, else: refuse(conn)
  end

  def call(%Plug.Conn{assigns: %{principal: %{}}} = conn, _opts), do: conn
  def call(conn, _opts), do: refuse(conn)

  @doc "The adapter contract's paths (spec §8, interface 2), the only ones an adapter's token opens."
  @spec adapter_path?(String.t(), [String.t()]) :: boolean()
  def adapter_path?("POST", ["v1", "residents", _id, "sessions"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "turn-start"]), do: true
  def adapter_path?("POST", ["v1", "residents", _id, "turns"]), do: true
  def adapter_path?("GET", ["v1", "residents", _id, "context"]), do: true
  def adapter_path?(_method, _path), do: false

  defp refuse(conn) do
    conn
    |> Helpers.error(401, Error.new(:gaia_not_a_principal))
    |> halt()
  end
end
