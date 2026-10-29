defmodule Oneiroi do
  @moduledoc """
  The core's top-level boundary. One coarse boundary today; the systems
  of spec §6 carve out of it as they land, each adopting
  `use Oneiroi.System`, and the boundary compiler is in the gate set from
  the first commit so the carving is enforced the moment it starts.

  ## The `deps:` list is the external surface, and it is checked

  External-dependency checking is armed in `mix.exs` for every application
  a :prod build can reach and Boundary can restrain, so a call into one of
  them from anywhere in this boundary is named here or the build fails.
  The substrate (`Oneiroi.Component`, `Oneiroi.Config` and the rest) is a
  path dependency, which Boundary cannot restrain without the cache defect
  `mix.exs` records, so it is reachable without an entry.

  ## The application root is its own boundary

  `Oneiroi.Application` starts the endpoint, and the web layer reaches
  back here for the roster and the health plug; one boundary holding
  both would be a dependency cycle, which Boundary refuses. So the
  application module is a top-level boundary of its own that depends on
  both and that nothing depends on: the composition point, outside the
  two things it composes.

  ## What it does not cover

  Boundary documents that calls to `:elixir`, `:boundary` and pure Erlang
  applications cannot be restrained. A module reaching a model provider
  through `:httpc` compiles clean here; conventions §11's one-port rule is
  the audit's `model_port` check when it lands with the port in P1, and
  naming which half is which is the difference between a gate and a
  belief about one.
  """
  use Boundary,
    deps: [
      # An implicit boundary covers a module namespace within one
      # application, so Ecto and Commanded are several entries each.
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Middleware.Pipeline,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Commanded.Serialization.JsonSerializer,
      Ecto,
      Ecto.Adapters.Postgres,
      Ecto.Adapters.SQL,
      Ecto.Adapters.SQL.Sandbox,
      Ecto.Changeset,
      Ecto.Migration,
      Ecto.Migrator,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Ecto.Type,
      EventStore,
      Jason,
      Oban,
      Pgvector,
      Phoenix.PubSub,
      Plug,
      Postgrex
    ],
    exports: [
      Actor,
      Boot,
      Commanded.Middleware.Actor,
      System,
      Command,
      Commanded,
      Event,
      Event.Codec,
      EventStore,
      Apsu,
      Apsu.Clock,
      Apsu.Clock.Fake,
      Apsu.HealthPlug,
      Apsu.Jobs,
      Apsu.PubSub,
      Apsu.Vault,
      Apsu.Vault.Encrypted,
      Projection,
      Repo,
      Router,
      Scope,
      Worker
    ]
end
