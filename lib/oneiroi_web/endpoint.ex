defmodule OneiroiWeb.Endpoint do
  @moduledoc """
  The one public listener. `/health` is answered ahead of the router by
  the platform's health plug; the built client and its storybook are
  served as static files; everything else is the router's.

  Function plugs rather than module plugs for the two core modules, so a
  compile-time dependency on them never lands on this file (the
  compile-connected ratchet is at zero and stays there).
  """
  use Phoenix.Endpoint, otp_app: :oneiroi

  # Aliases only; the calls below are runtime references, which is what
  # keeps the compile-connected count at zero (systems/platform.md #5).
  alias Oneiroi.Platform.HealthPlug
  alias OneiroiWeb.Router

  # `__Host-`, Secure, HttpOnly, Strict (spec §6.1): the cookie carries
  # the raw session id, signed; the store holds only its hash.
  @session_options [
    store: :cookie,
    key: "__Host-oneiroi",
    signing_salt: "oneiroi-session",
    same_site: "Strict",
    secure: true,
    http_only: true
  ]

  plug Plug.Static,
    at: "/",
    from: :oneiroi,
    gzip: not code_reloading?,
    only: ~w(client storybook favicon.ico robots.txt)

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  # The OpenAPI document is derived from the router, so the router cannot
  # mount it without a cycle; it is put on the conn here, before routing.
  # An atom rather than an alias, because `plug` is a macro and the alias
  # would be a compile-time dependency on a module that is only called
  # (the ratchet, `Oneiroi.Router` has the reasoning).
  plug OpenApiSpex.Plug.PutApiSpec, module: Module.concat([OneiroiWeb, ApiSpec])
  plug :health
  plug :router

  defp health(conn, _opts), do: HealthPlug.call(conn, HealthPlug.init([]))

  defp router(conn, _opts), do: Router.call(conn, Router.init([]))
end
