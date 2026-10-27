import Config

# The suite reads its values through the static source (conventions §9:
# no test reads the environment through the config layer), built from
# the same PG* variables CI provides. Every declared value is loaded at
# boot whether or not a test exercises it.
database_url =
  "ecto://#{System.get_env("PGUSER", "oneiroi")}:" <>
    "#{System.get_env("PGPASSWORD", "oneiroi")}@" <>
    "#{System.get_env("PGHOST", "localhost")}/#{System.get_env("PGDATABASE", "oneiroi_test")}"

config :oneiroi,
       :config_source,
       {Oneiroi.Config.Static,
        %{
          "DATABASE_URL" => database_url,
          "APSU_HTTP_PORT" => "4002",
          "APSU_SECRET_KEY_BASE" =>
            "test-secret-key-base-test-secret-key-base-test-secret-key-base-64",
          "APSU_VAULT_KEY" => "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
          # The sandbox checks out a connection per async test process, so
          # the pools are sized for the suite, not for the deployment.
          "APSU_POOL_SIZE" => "10",
          "APSU_EVENT_STORE_POOL_SIZE" => "10",
          "APSU_CLOCK" => "fake",
          "SIMA_QIAN_ROOT" => "tmp/sima_qian_test"
        }}

# The endpoint process runs (Phoenix.ConnTest needs it) and binds no socket.
config :oneiroi, serve: false

# The sandbox pool is a harness switch, not a connection parameter.
config :oneiroi, Oneiroi.Repo, pool: Ecto.Adapters.SQL.Sandbox

# Oban in manual testing mode: no queues run; jobs assert via Oban.Testing.
config :oneiroi, Oban, testing: :manual

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
