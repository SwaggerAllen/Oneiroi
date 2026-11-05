defmodule OneiroiWeb.Plugs.Switch do
  @moduledoc """
  Refuses a route whose contract switch is off for the resident in the
  path (agathos-daimon#34): `plug(Switch, [key: "research"] when action
  in [:ask])`, declared after the controller's own principal check, so
  only a party to the resident learns a switch is off.
  """
  @behaviour Plug

  import Plug.Conn

  alias Oneiroi.AgathosDaimon.Switches
  alias OneiroiWeb.Controllers.Helpers

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :key)

  @impl Plug
  def call(%Plug.Conn{halted: true} = conn, _key), do: conn

  def call(%Plug.Conn{path_params: %{"id" => id}} = conn, key) when is_binary(id) do
    if Oneiroi.AgathosDaimon.switch_on?(id, key) do
      conn
    else
      label = Switches.get(key).label

      conn
      |> Helpers.problem(
        403,
        :switched_off,
        :web_switch_off,
        "#{label} is switched off in the agreement; a version that turns it on, agreed by both, brings it back"
      )
      |> halt()
    end
  end

  def call(conn, _key), do: conn
end
