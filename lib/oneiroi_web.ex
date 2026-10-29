defmodule OneiroiWeb do
  @moduledoc """
  The web layer's boundary and use-macros: the endpoint, the router, the
  plugs and the JSON controllers of `/v1`. It reaches the core's exports
  and nothing under `Oneiroi.*` reaches it except the application root.
  """
  use Boundary,
    deps: [
      Oneiroi,
      Oneiroi.Gaia,
      Oneiroi.SimaQian,
      Oneiroi.AgathosDaimon,
      Oneiroi.Nisaba,
      Oneiroi.Kumbukumbu,
      Oneiroi.Brain,
      OpenApiSpex,
      OpenApiSpex.Plug.PutApiSpec,
      OpenApiSpex.Plug.RenderSpec,
      Phoenix,
      Phoenix.Channel,
      Phoenix.PubSub,
      Phoenix.Socket,
      Phoenix.Token,
      Plug
    ],
    exports: [Endpoint, UserSocket]

  @doc "The router macros: `use OneiroiWeb, :router`."
  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  @doc "Controller helpers: `use OneiroiWeb, :controller`."
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      use OpenApiSpex.ControllerSpecs

      import Plug.Conn
      import OneiroiWeb.Controllers.Helpers
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
