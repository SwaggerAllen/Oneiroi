defmodule Oneiroi.MixProject do
  use Mix.Project

  # Oneiroi: the core (design/oneiroi-spec.md), built per
  # design/p0-plan.md under design/conventions.md. Single OTP app plus
  # Boundary (conventions §4); Daedalus and the SDK are their own
  # mix projects under components/ and sdk/, each with its own gate block.
  def project do
    [
      app: :oneiroi,
      version: "0.1.0",
      # Floor, not pin: the pin is .tool-versions and CI enforces it.
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      boundary: boundary(),
      compilers: [:boundary] ++ Mix.compilers(),
      deps: deps(),
      hex: hex(),
      licensing: licensing()
    ]
  end

  # The core is served, never conveyed, so its own closure goes unchecked
  # (`{:service, :listed}` arms nothing); the list has to carry the core's
  # own identifier or its one subject reads as unplaceable. No `package:`
  # block: the core is published nowhere.
  defp licensing do
    [allow: ~w(AGPL-3.0-or-later Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]
  end

  # An advisory with no release to move to is acknowledged here per ID,
  # never per package and never by softening the gate (conventions §2).
  # Empty today; an entry matching nothing warns, so each one expires.
  defp hex do
    [ignore_advisories: []]
  end

  # External-dependency checking armed as `check: [apps: [...]]` rather
  # than `type: :strict`, for a measured reason: Boundary's cached view
  # drops a *path dep*'s boundaries on every incremental compile, so
  # strict reports every substrate call as forbidden on the second gate
  # run of a CI job. The list is what a :prod build can reach and
  # Boundary can restrain, and `mix oneiroi.audit`'s boundary-apps check
  # re-derives that set from the tree on every run and fails on an
  # omission; an application absent here is not partially checked, it is
  # exempt. Path deps, `:boundary` itself and applications with no Elixir
  # modules are excluded by derivation, never named.
  defp boundary do
    [
      default: [
        check: [
          apps: [
            :argon2_elixir,
            :backoff,
            :bandit,
            :commanded,
            :commanded_ecto_projections,
            :commanded_eventstore_adapter,
            :comeonin,
            :db_connection,
            :decimal,
            :ecto,
            :ecto_sql,
            :eventstore,
            :finch,
            :fsm,
            :gen_stage,
            :hpax,
            :jason,
            :logger_json,
            :mime,
            :mint,
            :nimble_options,
            :nimble_pool,
            :nimble_totp,
            :oban,
            :open_api_spex,
            :phoenix,
            :phoenix_pubsub,
            :pgvector,
            :phoenix_template,
            :plug,
            :plug_crypto,
            :postgrex,
            :req,
            :telemetry_registry,
            :thousand_island,
            :tz,
            :websock,
            :websock_adapter,
            :ymlr
          ]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Oneiroi.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:oneiroi_daedalus, path: "components/daedalus"},
      {:phoenix, "~> 1.8.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      # The persistence spine (plan P0.2, conventions §1's blessed list):
      # one Repo on Postgres, Commanded over EventStore for the event log,
      # Ecto projections, Oban for jobs.
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      # The vector column and its distance operators for the library's
      # index (spec §6.5; conventions §1's blessed list names pgvector).
      {:pgvector, "~> 0.4.2"},
      {:commanded, "~> 1.4"},
      {:commanded_eventstore_adapter, "~> 1.4"},
      {:eventstore, "~> 1.4"},
      {:commanded_ecto_projections, "~> 1.4"},
      {:oban, "~> 2.20"},
      # Identity (plan P0.4): argon2 hashes and TOTP second factors.
      {:argon2_elixir, "~> 4.1"},
      {:nimble_totp, "~> 1.0"},
      # The OpenAPI document the client generates from (spec §2.1).
      {:open_api_spex, "~> 3.21"},
      # The provider port's HTTP client (spec §2.1, conventions §1's
      # blessed list): OpenRouter over Req, in `Oneiroi.Nisaba.Provider`
      # and nowhere else, which the audit's `model_port` check holds.
      {:req, "~> 0.5"},
      # The IANA time zone database (spec §6.7: per resident, in the
      # resident's timezone). A new direct dependency, decided in
      # systems/sunna.md #10: `tz` bundles its data and takes no network
      # at runtime, which is what a gate with no network needs.
      {:tz, "~> 0.28"},
      # Structured JSON logs to stdout (conventions §10), prod only.
      {:logger_json, "~> 7.0"},
      {:stream_data, "~> 1.1", only: :test},
      {:ex_machina, "~> 2.8", only: :test},
      {:boundary, "~> 0.10", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # Armed from the first commit (conventions §2): the core has a public
      # endpoint, and the audit's own sleeper check reports a Phoenix tree
      # with no sobelow gate.
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # `hex.audit` first (the supply gate, reads the registry before
      # anything compiles), `mix_audit` second (a second opinion).
      "deps.audit": ["hex.audit", "deps.audit"],
      # The event store is not sandboxed (its own connection, its own
      # schema), so the suite starts from an empty store every run: drop,
      # create, migrate, test. Measured on the first run (plan: the store
      # reset per test run) and recorded in design/p0-plan.md.
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # The audit's globs are rooted at the working directory, so the
      # invoker that knows this repo has three mix projects lives here
      # and nowhere the shipped task could know a layout. It exits 1
      # rather than skipping when a project's deps are unresolved.
      "oneiroi.audit.all": [
        "oneiroi.audit",
        "cmd --cd components/daedalus mix oneiroi.audit",
        "cmd --cd sdk mix oneiroi.audit"
      ]
    ]
  end
end
