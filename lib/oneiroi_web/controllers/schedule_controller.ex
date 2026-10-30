defmodule OneiroiWeb.ScheduleController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Sunna
  alias OpenApiSpex.Schema

  tags(["schedule"])

  plug(:witnessed)

  @checkin_body {"check-in", "application/json",
                 %Schema{
                   type: :object,
                   required: [:label, :time],
                   properties: %{
                     label: %Schema{type: :string},
                     time: %Schema{type: :string, description: "HH:MM in the resident's zone"}
                   }
                 }}

  @date_body {"date", "application/json",
              %Schema{
                type: :object,
                required: [:title, :on, :kind],
                properties: %{
                  title: %Schema{type: :string},
                  on: %Schema{type: :string, format: :"date-time"},
                  kind: %Schema{type: :string, enum: ~w(deadline anniversary window recurring)}
                }
              }}

  operation(:today,
    summary:
      "Today in the resident's zone: check-ins with today's firings, the last and the next, free time, quiet hours, the dates with their countdowns derived now",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"today", "application/json", %Schema{type: :object}}]
  )

  def today(conn, %{"id" => id}), do: json(conn, id |> Sunna.today() |> today_json())

  operation(:days,
    summary: "The journal's day rows, newest first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"days", "application/json", %Schema{type: :array}}]
  )

  def days(conn, %{"id" => id}),
    do: json(conn, id |> Sunna.days(90) |> Enum.map(&%{day: &1.day, opened_at: &1.opened_at}))

  operation(:set_checkin,
    summary: "Add a check-in: a label and a time of day in the resident's zone",
    parameters: [id: [in: :path, type: :string]],
    request_body: @checkin_body,
    responses: [created: {"the key", "application/json", %Schema{type: :object}}]
  )

  def set_checkin(conn, %{"id" => id} = params) do
    case Sunna.set_checkin(id, nil, params["label"], params["time"], actor(conn)) do
      {:ok, key} -> conn |> put_status(201) |> json(%{key: key})
      other -> respond(conn, other)
    end
  end

  operation(:change_checkin,
    summary: "Change a check-in; one changed after its time today waits for tomorrow",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body: @checkin_body,
    responses: [no_content: "changed"]
  )

  def change_checkin(conn, %{"id" => id, "key" => key} = params) do
    case Sunna.set_checkin(id, key, params["label"], params["time"], actor(conn)) do
      {:ok, _key} -> send_resp(conn, 204, "")
      other -> respond(conn, other)
    end
  end

  operation(:delete_checkin,
    summary: "Delete a check-in",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    responses: [no_content: "deleted"]
  )

  def delete_checkin(conn, %{"id" => id, "key" => key}),
    do: respond(conn, Sunna.delete_checkin(id, key, actor(conn)))

  operation(:set_free_time,
    summary: "Set free time's time of day, or null for none",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"free time", "application/json",
       %Schema{type: :object, properties: %{time: %Schema{type: :string, nullable: true}}}},
    responses: [no_content: "set"]
  )

  def set_free_time(conn, %{"id" => id} = params),
    do: respond(conn, Sunna.set_free_time(id, params["time"], actor(conn)))

  operation(:set_quiet_hours,
    summary: "Set quiet hours from a time to a time (may cross midnight), or both null to clear",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"quiet hours", "application/json",
       %Schema{
         type: :object,
         properties: %{
           from: %Schema{type: :string, nullable: true},
           to: %Schema{type: :string, nullable: true}
         }
       }},
    responses: [no_content: "set"]
  )

  def set_quiet_hours(conn, %{"id" => id} = params),
    do: respond(conn, Sunna.set_quiet_hours(id, params["from"], params["to"], actor(conn)))

  operation(:dates,
    summary: "The important dates with their countdowns derived now",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"dates", "application/json", %Schema{type: :array}}]
  )

  def dates(conn, %{"id" => id}),
    do: json(conn, id |> Sunna.today() |> Map.fetch!(:dates) |> Enum.map(&date_json/1))

  operation(:set_date,
    summary: "Add an important date: a title, the instant, a kind",
    parameters: [id: [in: :path, type: :string]],
    request_body: @date_body,
    responses: [created: {"the number", "application/json", %Schema{type: :object}}]
  )

  def set_date(conn, %{"id" => id} = params) do
    case Sunna.set_date(id, nil, date_attrs(params), actor(conn)) do
      {:ok, number} -> conn |> put_status(201) |> json(%{number: number})
      other -> respond(conn, other)
    end
  end

  operation(:change_date,
    summary: "Change an important date",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body: @date_body,
    responses: [no_content: "changed"]
  )

  def change_date(conn, %{"id" => id, "number" => number} = params) do
    case Sunna.set_date(id, integer(number), date_attrs(params), actor(conn)) do
      {:ok, _number} -> send_resp(conn, 204, "")
      other -> respond(conn, other)
    end
  end

  operation(:remove_date,
    summary: "Remove an important date",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    responses: [no_content: "removed"]
  )

  def remove_date(conn, %{"id" => id, "number" => number}),
    do: respond(conn, Sunna.remove_date(id, integer(number), actor(conn)))

  # ---- shapes ----

  defp today_json(today) do
    %{
      day: today.day,
      now: today.now,
      timezone: today.timezone,
      checkins: Enum.map(today.checkins, &checkin_json/1),
      firings: Enum.map(today.firings, &firing_json/1),
      last: today.last,
      next: today.next,
      free_time: today.free_time,
      free_time_last: free_time_last(today.free_time_last),
      quiet: today.quiet,
      dates: Enum.map(today.dates, &date_json/1)
    }
  end

  defp checkin_json(c) do
    %{
      key: c.key,
      label: c.label,
      time: c.time,
      last_day: c.last_day,
      last_outcome: c.last_outcome,
      last_at: c.last_at
    }
  end

  defp firing_json(f), do: %{key: f.key, day: f.day, outcome: f.outcome, at: f.at, until: f.until}

  defp date_json(d) do
    %{number: d.number, title: d.title, on: d.on, kind: d.kind, days_to: d.days_to}
  end

  defp free_time_last({day, outcome}) when is_binary(day), do: %{day: day, outcome: outcome}
  defp free_time_last(_none), do: nil

  # A malformed instant arrives at the aggregate as nil and is refused
  # there as a time, so the one error names it.
  defp date_attrs(params) do
    on =
      case DateTime.from_iso8601(to_string(params["on"] || "")) do
        {:ok, at, _offset} -> at
        _other -> nil
      end

    %{title: params["title"], on: on, kind: params["kind"]}
  end

  # Every route here is a resident's, read or written by its witness.
  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_witnessed)) |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:sunna_no_such_checkin, :sunna_no_such_date],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
  defp respond(conn, {:error, reason}), do: problem(conn, 422, :refused, inspect(reason))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> 0
    end
  end
end
