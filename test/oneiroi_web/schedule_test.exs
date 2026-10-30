defmodule OneiroiWeb.ScheduleTest do
  @moduledoc "The schedule over HTTP: the witness sets the zone, check-ins, quiet hours, free time and dates, and reads today."
  use OneiroiWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Fixtures

  setup do
    Sandbox.start_owner!(Oneiroi.Repo, shared: true)
    |> then(&on_exit(fn -> Sandbox.stop_owner(&1) end))

    account = Fixtures.account!()
    resident = Fixtures.resident!(account)

    conn =
      build_conn()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())
      |> post("/v1/session", %{email: account.email, password: Fixtures.password()})
      |> recycle()
      |> put_req_header("origin", OneiroiWeb.Endpoint.url())

    {:ok, conn: conn, account: account, id: resident.id}
  end

  test "the whole schedule, set and read by its witness", %{conn: conn, id: id} do
    assert conn
           |> put("/v1/residents/#{id}/timezone", %{timezone: "Europe/London"})
           |> response(204)

    assert %{"error" => %{"kind" => "agathos_daimon_timezone_invalid"}} =
             conn
             |> put("/v1/residents/#{id}/timezone", %{timezone: "Mars/Olympus"})
             |> json_response(422)

    assert %{"timezone" => "Europe/London"} =
             conn |> get("/v1/residents/#{id}") |> json_response(200)

    assert %{"key" => key} =
             conn
             |> post("/v1/residents/#{id}/schedule/checkins", %{label: "morning", time: "06:00"})
             |> json_response(201)

    assert %{"error" => %{"kind" => "sunna_time_invalid"}} =
             conn
             |> post("/v1/residents/#{id}/schedule/checkins", %{label: "late", time: "25:00"})
             |> json_response(422)

    assert conn
           |> put("/v1/residents/#{id}/schedule/checkins/#{key}", %{
             label: "morning",
             time: "06:30"
           })
           |> response(204)

    assert conn
           |> put("/v1/residents/#{id}/schedule/free-time", %{time: "22:30"})
           |> response(204)

    assert conn
           |> put("/v1/residents/#{id}/schedule/quiet-hours", %{from: "23:00", to: "07:00"})
           |> response(204)

    assert %{"number" => 1} =
             conn
             |> post("/v1/residents/#{id}/dates", %{
               title: "visa interview",
               on: "2026-11-05T14:00:00Z",
               kind: "deadline"
             })
             |> json_response(201)

    assert %{"error" => %{"kind" => "sunna_time_invalid"}} =
             conn
             |> post("/v1/residents/#{id}/dates", %{title: "x", on: "next week", kind: "deadline"})
             |> json_response(422)

    assert %{
             "day" => "2026-10-26",
             "timezone" => "Europe/London",
             "checkins" => [%{"key" => ^key, "label" => "morning", "time" => "06:30"}],
             "firings" => [],
             "next" => %{"label" => "morning", "tomorrow" => true},
             "free_time" => "22:30",
             "free_time_last" => nil,
             "quiet" => %{"from" => "23:00", "to" => "07:00"},
             "dates" => [%{"number" => 1, "title" => "visa interview", "days_to" => 10}]
           } = conn |> get("/v1/residents/#{id}/schedule") |> json_response(200)

    assert [] = conn |> get("/v1/residents/#{id}/schedule/days") |> json_response(200)

    assert conn
           |> put("/v1/residents/#{id}/dates/1", %{
             title: "visa",
             on: "2026-11-06T14:00:00Z",
             kind: "deadline"
           })
           |> response(204)

    assert [%{"number" => 1, "title" => "visa", "days_to" => 11}] =
             conn |> get("/v1/residents/#{id}/dates") |> json_response(200)

    assert conn |> delete("/v1/residents/#{id}/dates/1") |> response(204)
    assert conn |> delete("/v1/residents/#{id}/dates/1") |> json_response(404)
    assert conn |> delete("/v1/residents/#{id}/schedule/checkins/#{key}") |> response(204)
    assert conn |> delete("/v1/residents/#{id}/schedule/checkins/#{key}") |> json_response(404)
  end

  test "another witness's resident is nobody's schedule", %{conn: conn} do
    other = Fixtures.resident!(Fixtures.account!())
    assert conn |> get("/v1/residents/#{other.id}/schedule") |> json_response(404)

    assert conn
           |> put("/v1/residents/#{other.id}/timezone", %{timezone: "Europe/London"})
           |> json_response(404)
  end
end
