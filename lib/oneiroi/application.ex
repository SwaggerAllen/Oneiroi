defmodule Oneiroi.Application do
  @moduledoc """
  The composed root (conventions §4): children come from the system
  registries via the composer, never by hand, after `Oneiroi.Boot` has
  validated the registries and loaded every declared value. A collision
  or a missing variable fails the boot with one report.

  The endpoint is always in the tree, test included (`Phoenix.ConnTest`
  needs the process); whether it binds a socket is `config :oneiroi,
  :serve`, and the port and secret are Apsu's declared
  settings.
  """
  use Application

  # A top-level boundary of its own, depending on both halves it composes
  # and depended on by neither (`Oneiroi`'s moduledoc).
  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.Gaia,
      Oneiroi.SimaQian,
      Oneiroi.AgathosDaimon,
      Oneiroi.HuginnMuninn,
      OneiroiWeb
    ]

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

  # A list rather than the options written inline in the tuple, because
  # the formatter lifts a comment inside `{Mod, key: ...}` above the
  # whole keyword list, and the comment on `url:` belongs beside it.
  defp endpoint_child do
    opts = [
      server: Application.get_env(:oneiroi, :serve, false),
      # The one unwrap in the tree today: the secret is declared
      # `secret: true`, and reaching its contents is a word a reviewer sees.
      secret_key_base: Secret.unwrap(Config.fetch!(:apsu, :secret_key_base)),
      # The origin the endpoint answers as. Without this line Phoenix
      # keeps its default localhost and the Origin check holds a browser
      # to the listener's name, which production did for a day (the
      # `public_url` declaration in Oneiroi.Apsu has the measurement).
      url: Config.fetch!(:apsu, :public_url),
      http: [ip: {0, 0, 0, 0}, port: Config.fetch!(:apsu, :http_port)]
    ]

    {OneiroiWeb.Endpoint, opts}
  end
end
