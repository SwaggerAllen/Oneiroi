defmodule Oneiroi.Boot do
  @moduledoc """
  What every entry point needs before anything else runs: the system
  roster, the config source, and the one call that validates the
  registries and loads every declared value.

  Its own module because the application is not the only entry point: a
  release task runs with the app loaded but not started, and a mix task
  starting the Repo (P0.2) calls `init/2` before any supervision tree
  exists. Both need configuration and neither boots the application.

  ## The source is chosen at compile time

  Reading an environment variable to decide whether to read environment
  variables is the circle it looks like, so the source rides
  `Application.compile_env`: the static fake in dev and test, seeded in
  `config/dev.exs` and `config/test.exs`, and `Oneiroi.Config.Env` in every
  real build, which cannot get the fake by omission.
  """

  alias Oneiroi.Component.Composer
  alias Oneiroi.Config

  @components Application.compile_env!(:oneiroi, :components)
  @config_source Application.compile_env(:oneiroi, :config_source, {Config.Env, []})

  @doc "The composed system roster, as declared in `config/config.exs`."
  @spec components() :: [module()]
  def components, do: @components

  @doc """
  Validates the registry set and loads every declared config value.

  Structure first (collisions, malformed declarations: a problem with no
  environment in it), then values. Both enumerate rather than stopping at
  the first problem. Idempotent, so an entry point may call it without
  knowing whether another already did.
  """
  @spec load!() :: :ok
  def load! do
    Composer.validate!(@components)
    Config.load!(@components, @config_source)
  end
end
