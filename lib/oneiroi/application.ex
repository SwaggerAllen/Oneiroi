defmodule Oneiroi.Application do
  @moduledoc """
  The composed root (conventions §4): children come from the system
  registries via the composer, never by hand, after `Oneiroi.Boot` has
  validated the registries and loaded every declared value. A collision
  or a missing variable fails the boot with one report.

  The endpoint is always in the tree, test included (`Phoenix.ConnTest`
  needs the process); whether it binds a socket is `config :oneiroi,
  :serve`, and the port and secret are the platform system's declared
  settings.
  """
  use Application

  # A top-level boundary of its own, depending on both halves it composes
  # and depended on by neither (`Oneiroi`'s moduledoc).
  use Boundary,
    top_level?: true,
    deps: [Oneiroi, Oneiroi.Identity, Oneiroi.Records, Oneiroi.Resident, OneiroiWeb]

  alias Oneiroi.Boot
  alias Oneiroi.Component.Composer
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret

  @impl Application
  def start(_type, _args) do
    Boot.load!()

    children =
      Composer.children(Boot.components()) ++ [endpoint_child()]

    Supervisor.start_link(children, strategy: :one_for_one, name: Oneiroi.Supervisor)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    OneiroiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp endpoint_child do
    {
      OneiroiWeb.Endpoint,
      # The one unwrap in the tree today: the secret is declared
      # `secret: true`, and reaching its contents is a word a reviewer sees.
      server: Application.get_env(:oneiroi, :serve, false),
      secret_key_base: Secret.unwrap(Config.fetch!(:platform, :secret_key_base)),
      http: [ip: {0, 0, 0, 0}, port: Config.fetch!(:platform, :http_port)]
    }
  end
end
