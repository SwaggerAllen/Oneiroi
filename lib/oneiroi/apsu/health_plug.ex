defmodule Oneiroi.Apsu.HealthPlug do
  @moduledoc """
  `/health` (conventions §10): Daedalus's health plug over the
  composed roster, mounted ahead of the router in `OneiroiWeb.Endpoint`
  and passing everything else through. The roster is read from
  `Oneiroi.Boot` at init so the endpoint names no system itself (root
  artifacts are composed, never edited).

  A matched request is halted explicitly: `send_resp/3` alone leaves
  `conn.halted` false, and the router behind this plug would then run on
  a connection already sent and raise on the missing route.
  """
  @behaviour Plug

  alias Oneiroi.Boot
  alias Oneiroi.Health

  @impl Plug
  def init(_opts), do: Health.init(components: Boot.components())

  @impl Plug
  def call(%Plug.Conn{path_info: ["health"]} = conn, health_opts) do
    conn |> Health.call(health_opts) |> Plug.Conn.halt()
  end

  def call(conn, _health_opts), do: conn
end
