defmodule Oneiroi.Commanded do
  @moduledoc """
  The Commanded application (conventions §6): one event log, Postgres in
  every environment through `Oneiroi.EventStore`, because the replay
  suite, the stream-naming scope and the rebuild round trip are claims
  about the real store (plan P0.2).

  Deliberately no `router/1` call here: that macro reads the router at
  this module's compile time, a compile-time dependency the ratchet is
  armed against. Each system's router names this application and is
  dispatched through on its own. The event store is named in
  `config/config.exs` rather than here for the same reason: an alias in
  the `use` options is a compile-time dependency on `Oneiroi.EventStore`.
  """
  use Commanded.Application, otp_app: :oneiroi
end
