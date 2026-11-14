defmodule OneiroiWeb.HourController do
  @moduledoc """
  The public hour (apsu#29), open to anyone, signed in or not: how the
  platform has performed over the last hour, in five-minute buckets,
  refreshed as each closes. Counts and timings, never content, nothing
  per resident, and a count under five as "few". Computed once a bucket,
  so reading it costs nothing however often.
  """
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["platform"])

  operation(:show,
    summary:
      "The last hour, public: each unit of work (a route, a job, a turn) with its count, failures, p50 and p95, mean query time and pool wait; the twelve five-minute buckets' trend; jobs waiting and failures by kind; when it next refreshes",
    responses: [ok: {"the hour", "application/json", %Schema{type: :object}}]
  )

  @doc "The hour with the platform's last start: its commit and when (gaia#21)."
  def with_deploy(hour) do
    case Oneiroi.Gaia.restarts(1) do
      [b | _] ->
        Map.merge(hour, %{
          commit: b.commit && String.slice(b.commit, 0, 12),
          deployed_at: b.booted_at
        })

      [] ->
        Map.merge(hour, %{commit: nil, deployed_at: nil})
    end
  end

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=60")
    |> json(with_deploy(Oneiroi.Apsu.hour()))
  end
end
