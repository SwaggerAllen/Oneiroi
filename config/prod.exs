import Config

# Values a deployment differs on are declared in a system's `config/0`
# and loaded once at boot through `Oneiroi.Config.Env`, the compile-time
# default, so a real build cannot get the static fake by omission
# (`Oneiroi.Boot`). What stays here selects the build: this one serves.
config :oneiroi, serve: true

config :logger, level: :info
