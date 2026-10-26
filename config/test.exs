import Config

# The suite reads its values through the static source (conventions §9:
# no test reads the environment through the config layer). Every
# declared value is loaded at boot whether or not a test exercises it.
config :oneiroi,
       :config_source,
       {Oneiroi.Config.Static,
        %{
          "PLATFORM_HTTP_PORT" => "4002",
          "PLATFORM_SECRET_KEY_BASE" =>
            "test-secret-key-base-test-secret-key-base-test-secret-key-base-64"
        }}

# The endpoint process runs (Phoenix.ConnTest needs it) and binds no socket.
config :oneiroi, serve: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
