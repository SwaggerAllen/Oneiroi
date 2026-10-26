defmodule OneiroiWeb do
  @moduledoc """
  The web layer's boundary and use-macros: the endpoint, the router and
  the JSON surface. It reaches the core for the roster and the health
  plug and nothing under `Oneiroi.*` reaches it except the application
  that starts the endpoint.
  """
  use Boundary,
    deps: [
      Oneiroi,
      Phoenix,
      Phoenix.PubSub,
      Plug
    ],
    exports: [Endpoint]

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

      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
