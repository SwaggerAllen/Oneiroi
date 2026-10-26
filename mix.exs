defmodule Oneiroi.MixProject do
  use Mix.Project

  # Oneiroi: the core (design/oneiroi-spec.md), built per
  # design/p0-plan.md under design/conventions.md. Single OTP app plus
  # Boundary (conventions §4); the substrate and the SDK are their own
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
            :bandit,
            :hpax,
            :jason,
            :mime,
            :phoenix,
            :phoenix_pubsub,
            :phoenix_template,
            :plug,
            :plug_crypto,
            :thousand_island,
            :websock,
            :websock_adapter
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
      {:oneiroi_substrate, path: "components/substrate"},
      {:phoenix, "~> 1.8.1"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
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
      # The audit's globs are rooted at the working directory, so the
      # invoker that knows this repo has three mix projects lives here
      # and nowhere the shipped task could know a layout. It exits 1
      # rather than skipping when a project's deps are unresolved.
      "oneiroi.audit.all": [
        "oneiroi.audit",
        "cmd --cd components/substrate mix oneiroi.audit",
        "cmd --cd sdk mix oneiroi.audit"
      ]
    ]
  end
end
