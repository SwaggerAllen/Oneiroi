defmodule OneiroiWeb.Plugs.RequirePrincipal do
  @moduledoc "Halts with 401 when `OneiroiWeb.Plugs.Authenticate` found no principal."
  @behaviour Plug

  import Plug.Conn

  alias Oneiroi.Gaia.Error
  alias OneiroiWeb.Controllers.Helpers

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{assigns: %{principal: %{}}} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn
    |> Helpers.error(401, Error.new(:gaia_not_a_principal))
    |> halt()
  end
end
