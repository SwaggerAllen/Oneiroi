defmodule OneiroiWeb.Metrics.Grafana do
  @moduledoc """
  What the PromEx dashboards need on Grafana Cloud before they are
  uploaded (apsu#33), applied to each decoded dashboard through PromEx's
  `apply_function`, so every boot's upload carries the fixes rather than
  overwriting the hand-made ones (the witness and Grafana's assistant
  found them by hand on 2026-11-14):

  - the hosted scrape (the Metrics Endpoint integration) puts no
    `instance` label on a series, so every `instance="$instance"` matcher
    matched nothing: each is taken out, and the Instance variable with
    them;
  - the Job variable's saved default, `elixir_app` in PromEx's Oban
    dashboard, names a job that does not exist: no saved default, so
    Grafana picks the real one;
  - the scrape runs every two minutes, so an `irate` over 30 s holds
    fewer than its two samples: the Interval variable starts at
    `APSU_GRAFANA_INTERVAL` (4m) and offers nothing shorter;
  - PromEx's histogram buckets are labelled `500.0` and `1000.0`, so the
    Apdex panels' `le="500"` and `le="1000"` matched nothing.
  """

  @intervals ~w(4m 5m 15m 30m 1h)

  @doc "The dashboard with the hosted-Grafana fixes applied; `interval` the Interval variable's first choice."
  @spec fixup(map(), String.t()) :: map()
  def fixup(%{} = dashboard, interval) do
    dashboard
    |> walk(&expression/1)
    |> Map.update("templating", %{}, &templating(&1, interval))
  end

  defp walk(%{} = map, fun), do: Map.new(map, fn {k, v} -> {k, walk(v, fun)} end)
  defp walk(list, fun) when is_list(list), do: Enum.map(list, &walk(&1, fun))
  defp walk(text, fun) when is_binary(text), do: fun.(text)
  defp walk(other, _fun), do: other

  @doc false
  @spec expression(String.t()) :: String.t()
  def expression(text) do
    text
    |> String.replace(~r/,\s*instance="\$instance"/, "")
    |> String.replace(~r/instance="\$instance"\s*,\s*/, "")
    |> String.replace(~r/\{\s*instance="\$instance"\s*\}/, "")
    |> String.replace(~s(le="500"), ~s(le="500.0"))
    |> String.replace(~s(le="1000"), ~s(le="1000.0"))
  end

  defp templating(%{"list" => list} = templating, interval) do
    list =
      list
      |> Enum.reject(&(&1["name"] == "instance"))
      |> Enum.map(fn
        %{"name" => "job"} = job -> Map.delete(job, "current")
        %{"name" => "interval"} = var -> interval_variable(var, interval)
        var -> var
      end)

    %{templating | "list" => list}
  end

  defp templating(templating, _interval), do: templating

  defp interval_variable(var, interval) do
    choices = Enum.uniq([interval | @intervals])
    option = &%{"selected" => &1 == interval, "text" => &1, "value" => &1}

    Map.merge(var, %{
      "current" => %{"selected" => true, "text" => interval, "value" => interval},
      "options" => Enum.map(choices, option),
      "query" => Enum.join(choices, ",")
    })
  end
end
