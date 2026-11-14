defmodule Oneiroi.Apsu.SpansTest do
  @moduledoc """
  Where the time goes (apsu#25 to #28): a unit of work's totals (its
  queries, their time and pool wait, its exports, the events it
  dispatched) kept as a row when slow, read back by name and summarised;
  every export one histogram; every event stamped with its trace id; the
  scrape closed without its token.
  """
  use OneiroiWeb.ConnCase, async: false

  alias Commanded.Middleware.Pipeline
  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Spans
  alias Oneiroi.Commanded.Middleware.Actor, as: Middleware
  alias Oneiroi.Fixtures

  defmodule Ping do
    use Oneiroi.Command, fields: [:id]
  end

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    :ok
  end

  defp native(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  # The collector writes from its own process every few seconds; a test
  # asks it to write now.
  defp flush do
    send(:apsu_spans, :flush)
    :sys.get_state(:apsu_spans)
  end

  test "a slow request keeps its totals, exports and events, read back slowest first and summarised" do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)

    # The collector's handlers are called as telemetry would call them;
    # executing the router's own events would reach Phoenix's handlers
    # with a conn they cannot read.
    Spans.root(
      [:phoenix, :router_dispatch, :start],
      %{},
      %{
        conn: %{method: "GET", path_params: %{"id" => resident.id}},
        route: "/v1/residents/:id/slow"
      },
      :http
    )

    # Work inside it: an export (with its queries) and a dispatch's events.
    _ = Oneiroi.Brain.needs_you(resident.id)

    :telemetry.execute([:oneiroi, :apsu, :dispatch], %{count: 2}, %{
      events: ["WorkAdded", "WorkAdded"]
    })

    Spans.root([:phoenix, :router_dispatch, :stop], %{duration: native(1_200)}, %{}, :http)
    flush()

    assert [row] = Oneiroi.Apsu.spans(%{name: "/slow"})
    assert row.kind == "http"
    assert row.name == "GET /v1/residents/:id/slow"
    assert row.subject_id == resident.id
    assert row.duration_ms == 1_200
    assert row.db_count > 0
    assert %{"brain.needs_you" => %{"count" => 1}} = row.exports
    assert row.events == %{"WorkAdded" => 2}
    assert is_binary(row.trace_id)

    assert [%{name: "GET /v1/residents/:id/slow", rows: 1, p95_ms: 1_200}] =
             Enum.filter(Oneiroi.Apsu.span_summary(%{}), &(&1.name =~ "/slow"))
  end

  test "a fast request outside the sample is not kept, and a nested unit counts to the outer one" do
    Spans.root(
      [:phoenix, :router_dispatch, :start],
      %{},
      %{route: "/fast", conn: %{method: "GET"}},
      :http
    )

    Spans.root([:oban, :job, :start], %{}, %{job: %{worker: "Inner", args: %{}}}, :job)
    Spans.root([:oban, :job, :stop], %{duration: native(5)}, %{}, :job)
    # Still inside the outer unit.
    assert Process.get({Oneiroi.Apsu.Spans, :span}).name == "GET /fast"
    Spans.root([:phoenix, :router_dispatch, :stop], %{duration: native(1)}, %{}, :http)
    flush()

    # The sample is 1%: a single fast row is almost always dropped, never a slow one.
    assert Oneiroi.Apsu.spans(%{name: "Inner"}) == []
  end

  test "every event a dispatch writes carries the trace id of the work that dispatched it (apsu#27)" do
    Logger.metadata(trace_id: "feedc0de")

    pipeline = %Pipeline{
      command: %Ping{actor: Actor.platform(), at: DateTime.utc_now(), id: "x"},
      metadata: %{}
    }

    assert %Pipeline{metadata: %{"trace_id" => "feedc0de"}} = Middleware.before_dispatch(pipeline)
  after
    Logger.metadata(trace_id: nil)
  end

  test "every export lands in one histogram, and /metrics is closed without its token", %{
    conn: conn
  } do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    _ = Oneiroi.Brain.needs_you(resident.id)

    text = PromEx.get_metrics(OneiroiWeb.Metrics)

    assert text =~
             ~s(oneiroi_export_duration_milliseconds_bucket{component="brain",function="needs_you")

    assert conn |> get("/metrics") |> response(404)
  end
end
