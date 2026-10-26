import Config

# The system roster the composer validates and composes (conventions §4).
# Grows one entry per system as they land; `Oneiroi.Boot` reads it.
config :oneiroi, :components, [Oneiroi.Platform]

# Build-shape endpoint config: the port and the secret are instance
# shape and come from the platform system's `config/0` at boot instead
# (`Oneiroi.Application`), so this file names no value a deployment
# differs on.
config :oneiroi, OneiroiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: OneiroiWeb.ErrorJSON], layout: false],
  pubsub_server: :platform_pubsub

# The export macro's Logger metadata floor (`Oneiroi.Component.API`):
# `component:` at every boundary entry and `trace_id:` at the root of a
# trace. Declared here because Logger drops metadata keys the formatter
# was never told about. Structured JSON output is P0.2's (plan §P0.2).
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:component, :trace_id, :request_id]

config :phoenix, :json_library, Jason

# Whether this build binds a socket at all; the port is a declared
# setting. Dev and prod serve, test does not.
config :oneiroi, serve: false

import_config "#{config_env()}.exs"
