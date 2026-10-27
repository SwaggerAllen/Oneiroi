defmodule Oneiroi.SDK.MixProject do
  use Mix.Project

  # The adapter SDK (spec §8, conventions §1): the package another agent
  # platform embeds to speak Oneiroi's three adapter interfaces. Its own
  # mix project rather than a directory of the core, because the core is
  # AGPL and this is Apache-2.0: a path dependency on Daedalus is the
  # only code it shares, and `mix oneiroi.audit`'s license check holds the
  # closure to the allow list below.
  def project do
    [
      app: :oneiroi_sdk,
      version: "0.1.0",
      # Floor, not pin: the pin is .tool-versions and CI enforces it.
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      licensing: licensing()
    ]
  end

  # `licenses:` is what arms the license check: a project with a package
  # block is fetched by somebody, and being fetched is what conveyance is.
  defp package do
    [licenses: ["Apache-2.0"]]
  end

  # The criterion is "imposes no terms on the linking application", not
  # "permissive"; ISC is here because cowboy, cowlib and ranch carry it.
  # The core's AGPL is deliberately absent: a copyleft dependency under
  # this tree fails the audit, which is the whole of conventions §1's
  # license gate.
  defp licensing do
    [allow: ~w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:oneiroi_daedalus, path: "../components/daedalus"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
