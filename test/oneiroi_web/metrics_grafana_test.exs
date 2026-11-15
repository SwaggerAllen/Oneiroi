defmodule OneiroiWeb.MetricsGrafanaTest do
  @moduledoc """
  The dashboards as they are uploaded (apsu#33): each rendered and fixed
  through the same pipeline PromEx's uploader runs, then read for the
  four fixes the hosted Grafana needed by hand on 2026-11-14.
  """
  use ExUnit.Case, async: true

  alias PromEx.DashboardRenderer

  # PromEx's uploader, step for step (PromEx.DashboardUploader).
  defp uploaded({otp_app, path, opts}) do
    {apply_function, opts} = Keyword.pop(opts, :apply_function, & &1)

    otp_app
    |> DashboardRenderer.build(path, :oneiroi)
    |> DashboardRenderer.merge_assigns(otp_app: :oneiroi)
    |> DashboardRenderer.merge_assigns(OneiroiWeb.Metrics.dashboard_assigns())
    |> DashboardRenderer.merge_assigns(title: "Oneiroi - #{path}")
    |> DashboardRenderer.merge_assigns(opts)
    |> DashboardRenderer.render_dashboard(OneiroiWeb.Metrics)
    |> DashboardRenderer.decode_dashboard()
    |> DashboardRenderer.apply_dashboard_function(apply_function)
  end

  defp prom_ex_dashboards,
    do: for({:prom_ex, _path, _opts} = d <- OneiroiWeb.Metrics.dashboards(), do: d)

  test "every PromEx dashboard leaves out the instance the hosted scrape never labels, and starts at the scrape's interval" do
    assert length(prom_ex_dashboards()) == 5

    for {_, path, _} = d <- prom_ex_dashboards() do
      %DashboardRenderer{valid_json?: true, decoded_dashboard: dash} = uploaded(d)
      text = Jason.encode!(dash)

      refute text =~ ~s(instance=\\"$instance\\"), path
      refute text =~ ~s("uid":"prometheus"), path
      assert text =~ "grafanacloud-prom", path

      vars = dash["templating"]["list"]
      refute Enum.any?(vars, &(&1["name"] == "instance")), path
      refute Enum.any?(vars, &(&1["name"] == "job" and Map.has_key?(&1, "current"))), path

      case Enum.find(vars, &(&1["name"] == "interval")) do
        nil ->
          :no_interval

        interval ->
          assert interval["current"]["value"] == "4m", path
          refute Enum.any?(interval["options"], &(&1["value"] in ["15s", "30s", "1m"])), path
      end
    end
  end

  test "the Apdex panels read PromEx's bucket labels as they are written" do
    {_, _, _} = phoenix = Enum.find(prom_ex_dashboards(), &(elem(&1, 1) == "phoenix.json"))
    text = phoenix |> uploaded() |> Map.fetch!(:decoded_dashboard) |> Jason.encode!()
    assert text =~ ~s(le=\\"500.0\\")
    assert text =~ ~s(le=\\"1000.0\\")
    refute text =~ ~s(le=\\"500\\")
  end

  test "an expression keeps every other matcher" do
    alias OneiroiWeb.Metrics.Grafana

    assert Grafana.expression(~s(m{job="$job", instance="$instance", le="500"})) ==
             ~s(m{job="$job", le="500.0"})

    assert Grafana.expression(~s(m{instance="$instance", job="$job"})) == ~s(m{job="$job"})
    assert Grafana.expression(~s(m{instance="$instance"})) == "m"
  end
end
