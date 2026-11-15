defmodule OneiroiWeb.Metrics do
  @moduledoc """
  Metrics (apsu#25; the witness, 2026-11-13: PromEx and a hosted Grafana,
  with the span work, as one piece). Prometheus text off the telemetry the
  app already emits: the BEAM, the endpoint's requests by route, the
  Repo's queries (their time and the time each waited for a connection),
  Oban's jobs, every boundary export's duration, and the span collector's
  units of work (`OneiroiWeb.Metrics.Work`). Scraped at `/metrics` with
  the bearer token `APSU_METRICS_TOKEN` (`OneiroiWeb.MetricsPlug`); the
  dashboards are uploaded to `APSU_GRAFANA_URL` on boot when it and
  `APSU_GRAFANA_TOKEN` are set (`OneiroiWeb.Metrics.Setup`).

  Here rather than in the platform system because the Phoenix plugin
  names the router and the endpoint, which the core never may.
  """
  use PromEx, otp_app: :oneiroi

  alias OneiroiWeb.Metrics.Grafana
  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      # Atoms, not aliases: the endpoint calls the scrape, which reads this
      # module, so naming the endpoint here would close a cycle (the
      # cycles gate; `Oneiroi.Router` has the reasoning).
      {Plugins.Phoenix,
       router: Module.concat([OneiroiWeb, Router]),
       endpoint: Module.concat([OneiroiWeb, Endpoint])},
      {Plugins.Ecto, repos: [Oneiroi.Repo]},
      {Plugins.Oban, oban_supervisors: [Oban]},
      OneiroiWeb.Metrics.Work
    ]
  end

  @impl true
  def dashboard_assigns,
    do: [
      datasource_id: Oneiroi.Config.fetch!(:apsu, :grafana_datasource),
      default_selected_interval: Oneiroi.Config.fetch!(:apsu, :grafana_interval)
    ]

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json", apply_function: &fixup/1},
      {:prom_ex, "beam.json", apply_function: &fixup/1},
      {:prom_ex, "phoenix.json", apply_function: &fixup/1},
      {:prom_ex, "ecto.json", apply_function: &fixup/1},
      {:prom_ex, "oban.json", apply_function: &fixup/1},
      {:oneiroi, "grafana/work.json"}
    ]
  end

  # The hosted Grafana's fixes (apsu#33), applied to each PromEx dashboard
  # before it is uploaded.
  defp fixup(dashboard),
    do: Grafana.fixup(dashboard, Oneiroi.Config.fetch!(:apsu, :grafana_interval))
end
