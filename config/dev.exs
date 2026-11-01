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
          "DATABASE_URL" => "ecto://oneiroi:oneiroi@localhost/oneiroi_dev",
          "APSU_HTTP_PORT" => "4000",
          # Render's name for the service's own origin (Oneiroi.Apsu); in
          # dev the listener is it.
          "RENDER_EXTERNAL_URL" => "http://localhost:4000",
          "APSU_SECRET_KEY_BASE" =>
            "dev-secret-key-base-dev-secret-key-base-dev-secret-key-base-padded",
          # 32 zero bytes, base64: a dev key, never a deployment's.
          "APSU_VAULT_KEY" => "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
          "APSU_CLOCK" => "system",
          # Dev talks to OpenRouter on the witness's own key, as a deployment does.
          "NISABA_PROVIDER" => "openrouter",
          "SIMA_QIAN_ROOT" => "tmp/sima_qian_dev"
        }}

config :oneiroi, serve: true

config :oneiroi, OneiroiWeb.Endpoint,
  check_origin: false,
  code_reloader: true,
  debug_errors: true

config :logger, :default_formatter, format: "[$level] $metadata$message\n"

config :logger, :default_handler,
  formatter:
    {Oneiroi.Log.Redacting,
     Logger.Formatter.new(
       format: "[$level] $metadata$message\n",
       metadata: [:component, :trace_id, :request_id]
     )}

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
