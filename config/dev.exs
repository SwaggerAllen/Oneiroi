import Config

# Dev reads its values through the static source, not the environment:
# the values live in this file, under review, so there is no untracked
# dotenv to explain when one machine behaves differently from another.
# Every value is a string and goes through its declared cast, exactly
# as a deployment's would.
config :oneiroi,
       :config_source,
       {Oneiroi.Config.Static,
        %{
          "PLATFORM_HTTP_PORT" => "4000",
          "PLATFORM_SECRET_KEY_BASE" =>
            "dev-secret-key-base-dev-secret-key-base-dev-secret-key-base-padded"
        }}

config :oneiroi, serve: true

config :oneiroi, OneiroiWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true

config :logger, :default_formatter, format: "[$level] $metadata$message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
