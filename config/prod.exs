import Config

# Values a deployment differs on are declared in a system's `config/0`
# and loaded once at boot through `Oneiroi.Config.Env`, the compile-time
# default, so a real build cannot get the static fake by omission
# (`Oneiroi.Boot`). What stays here selects the build: this one serves,
# and logs structured JSON to stdout (conventions §10), the write-only
# channel nothing parses.
config :oneiroi, serve: true

config :logger, :default_handler,
  formatter: LoggerJSON.Formatters.Basic.new(metadata: [:component, :trace_id, :request_id])

config :logger, level: :info
