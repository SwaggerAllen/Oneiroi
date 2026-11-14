defmodule OneiroiWeb.OpsController do
  @moduledoc """
  The ops read surface (apsu#23; design/logging-and-alerting.md step 1):
  facts about what failed and what has stopped happening, never content.

  - `GET /v1/ops/failures`, the operator's: the in-process failure ring
    (`Oneiroi.Apsu.Ops`), narrowed by kind, site, component or trace id,
    and the jobs Oban discarded in the last day. Platform-wide, so a
    super admin's alone.
  - `GET /v1/residents/:id/ops/heartbeats`, the witness's: when each
    thing that always happens for this resident last did, against how
    often it should, read from the records where they already are
    (backup, free time, rounds) and the adapters' last asks of `/waiting`.
    A heartbeat interprets nothing; it says "this has not happened".
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Ops
  alias OpenApiSpex.Schema

  tags(["ops"])

  plug(:operator when action in [:failures, :spans, :span_summary])
  plug(:witnessed when action in [:heartbeats])

  @hour 3600

  operation(:failures,
    summary:
      "The last warnings and errors the platform logged, as facts (when, level, component, kind, site, cause, trace id, the message trimmed and scrubbed), and the jobs discarded in the last day",
    parameters: [
      kind: [in: :query, type: :string],
      site: [in: :query, type: :string],
      component: [in: :query, type: :string],
      trace_id: [in: :query, type: :string]
    ],
    responses: [ok: {"failures", "application/json", %Schema{type: :object}}]
  )

  def failures(conn, params) do
    filters = %{
      error_kind: params["kind"],
      error_site: params["site"],
      component: params["component"],
      trace_id: params["trace_id"]
    }

    since = DateTime.add(Clock.now(), -24 * @hour, :second)
    json(conn, %{failures: Ops.failures(filters), discarded_jobs: Ops.discarded_jobs(since)})
  end

  operation(:spans,
    summary:
      "The slowest requests, jobs and turns in a window (apsu#28): each with its time, its time in queries and waiting for a database connection, its slowest exports, the events it dispatched, the resident it served and its trace id; never content",
    parameters: [
      hours: [
        in: :query,
        type: :integer,
        description: "the window, 1 to 720 hours back; 24 by default"
      ],
      name: [in: :query, type: :string, description: "a phrase of the route, worker or turn"],
      kind: [in: :query, type: :string, description: "http, job or turn"],
      subject: [in: :query, type: :string, description: "a resident id"],
      trace_id: [in: :query, type: :string],
      min_ms: [in: :query, type: :integer],
      limit: [in: :query, type: :integer, description: "at most 500; 100 by default"]
    ],
    responses: [ok: {"spans", "application/json", %Schema{type: :array}}]
  )

  def spans(conn, params) do
    json(
      conn,
      Oneiroi.Apsu.spans(%{
        hours: int(params["hours"]),
        name: params["name"],
        kind: params["kind"],
        subject: params["subject"],
        trace_id: params["trace_id"],
        min_ms: int(params["min_ms"]),
        limit: int(params["limit"])
      })
    )
  end

  operation(:span_summary,
    summary:
      "The span rows by unit of work in a window (apsu#28): how many, p50, p95 and longest, mean time in queries, waiting for a connection and queries run, slowest p95 first",
    parameters: [hours: [in: :query, type: :integer]],
    responses: [ok: {"summary", "application/json", %Schema{type: :array}}]
  )

  def span_summary(conn, params),
    do: json(conn, Oneiroi.Apsu.span_summary(%{hours: int(params["hours"])}))

  defp int(nil), do: nil

  defp int(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _other -> nil
    end
  end

  operation(:heartbeats,
    summary:
      "When each recurring thing last happened for the resident, how often it should, and whether it is late: backup, free time, rounds, each adapter's last ask of /waiting",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"heartbeats", "application/json", %Schema{type: :array}}]
  )

  def heartbeats(conn, %{"id" => id}) do
    {:ok, row} = AgathosDaimon.fetch(id)
    now = Clock.now()

    beats =
      backup(row) ++ free_time(id) ++ rounds(id) ++ adapters(id)

    json(conn, Enum.map(beats, &late(&1, now)))
  end

  defp backup(%{remote_url: url} = row) when is_binary(url),
    do: [%{name: "backup", last: row.last_backup_at, every_seconds: 26 * @hour}]

  defp backup(_row), do: []

  defp free_time(id) do
    last =
      id
      |> Oneiroi.Sunna.free_time_history(10)
      |> Enum.find(&(&1.outcome == "ran"))

    [%{name: "free time", last: last && last.at, every_seconds: 26 * @hour}]
  end

  defp rounds(id) do
    case Oneiroi.Sunna.today(id).rounds do
      %{every_hours: every, last_at: last} when every > 0 ->
        # Rounds sleep through the night: a waking day's gap, not the cadence.
        [%{name: "rounds", last: last, every_seconds: 14 * @hour}]

      _off ->
        []
    end
  end

  # The reader asks every five minutes; a brain adapter asks only while its
  # runtime is open, so it is shown without a bound.
  defp adapters(id) do
    for a <- AgathosDaimon.adapters(id), is_nil(a.revoked_at) do
      %{
        name: "adapter #{a.adapter} (#{a.role})",
        last: Ops.last_beat("#{id}:#{a.adapter}"),
        every_seconds: if(a.role == "reader", do: 30 * 60, else: nil)
      }
    end
  end

  defp late(%{last: last, every_seconds: every} = beat, now) do
    late? =
      cond do
        is_nil(every) -> false
        is_nil(last) -> true
        true -> DateTime.diff(now, last, :second) > every
      end

    Map.put(beat, :late, late?)
  end

  defp operator(%{assigns: %{principal: %{account_id: id}}} = conn, _opts) when is_binary(id) do
    if Oneiroi.Gaia.operator?(id), do: conn, else: refuse(conn)
  end

  defp operator(conn, _opts), do: refuse(conn)

  defp refuse(conn),
    do:
      conn
      |> problem(
        403,
        :not_an_operator,
        :web_ops_not_operator,
        "only a super admin reads the platform's failures"
      )
      |> halt()

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(:agathos_daimon_not_witnessed, :agathos_daimon_web_ops_not_witnessed)
        )
        |> halt()
  end
end
