import Config

# Values a deployment differs on are declared in a system's `config/0`
# and loaded once at boot through `Oneiroi.Config.Env`, the compile-time
# default, so a real build cannot get the static fake by omission
# (`Oneiroi.Boot`). What stays here selects the build: this one serves,
# and logs structured JSON to stdout (conventions §10), the write-only
# channel nothing parses.
config :oneiroi, serve: true

# The tuple form, never `LoggerJSON.Formatters.Basic.new/1`: config is
# evaluated by every mix command, `mix deps.get` included, and in the
# release build the dependency does not exist yet when it runs, so a
# function call here fails the image at its first step. The tuple names
# the module and the logger calls it once the handler starts. The test
# environment never saw this because its deps were already compiled.
#
# `Oneiroi.Log.Redacting` wraps it, as in every environment: the
# credential backstop scrubs the line LoggerJSON produced.
config :logger, :default_handler,
  formatter:
    {Oneiroi.Log.Redacting,
     {LoggerJSON.Formatters.Basic,
      metadata: [:component, :trace_id, :request_id, :error_kind, :error_site, :error_cause]}}

config :logger, level: :info
