defmodule OneiroiWeb.DayController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna
  alias OpenApiSpex.Schema

  tags(["schedule"])

  plug(:witnessed)

  operation(:index,
    summary:
      "The calendar's days (sunna#48): every local day in the resident's zone from `from` to `to` (ISO dates, both included and required, at most SUNNA_DAYS_SPAN, 62), oldest first. `{from, to, today, zone, witness_reads, days: [{day, journal, story: {sessions, scenes, complete}, schedule}]}`. `journal` is the day's marks (counts of plan, note, todo, done, wrap and `unwrapped`), null when she wrote nothing; `story.sessions` the sessions spoken in that day with their first and last instants and message counts (kumbukumbu#59), a locked one by its row's receipts with no count; `story.scenes` the day's scenes (seshat#52) with their titles and times, `complete` whether the bedtime pass closed the day (null with no scenes). With the agreement's `witness_reads` off, `journal`, `scenes` and `complete` are null on every day. `schedule` is null on a past day; on today and after, `{quiet, rounds, entries}`, the entries computed from the rules as they stand (check-ins deferred past quiet hours, free time, one-offs, dates), each `{kind, key, label, time, at, rule, status}`",
    parameters: [
      id: [in: :path, type: :string],
      from: [in: :query, type: :string, required: true],
      to: [in: :query, type: :string, required: true]
    ],
    responses: [
      ok: {"the days", "application/json", %Schema{type: :object}},
      unprocessable_entity:
        {"a bound that is no date, a range backwards, or one too long", "application/json",
         %Schema{type: :object}}
    ]
  )

  def index(%{assigns: %{principal: p}} = conn, %{"id" => id} = params) do
    with {:ok, range} <- Sunna.days_range(id, params["from"], params["to"]),
         {:ok, sessions} <-
           Kumbukumbu.session_days({:account, p.account_id}, id, range.from, range.to) do
      reads = AgathosDaimon.switch_on?(id, "witness_reads")
      schedules = Sunna.day_schedules(id, range.days)

      {marks, scenes} =
        if reads,
          do:
            {Seshat.journal_marks(id, range.days),
             Map.new(Seshat.scenes(id, range.from, range.to), &{&1.day, &1})},
          else: {%{}, %{}}

      days =
        for day <- range.days do
          %{
            day: day,
            journal: Map.get(marks, day),
            story: story(reads, Map.get(sessions, day, []), Map.get(scenes, day)),
            schedule: Map.get(schedules, day)
          }
        end

      json(conn, %{
        from: range.from,
        to: range.to,
        today: range.today,
        zone: range.zone,
        witness_reads: reads,
        days: days
      })
    else
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp story(false, sessions, _scenes), do: %{sessions: sessions, scenes: nil, complete: nil}
  defp story(true, sessions, nil), do: %{sessions: sessions, scenes: [], complete: nil}

  defp story(true, sessions, day),
    do: %{sessions: sessions, scenes: Enum.map(day.scenes, &scene/1), complete: day.complete}

  # The scene's place in the day, not its summary: that is `/scenes`'s.
  defp scene(s),
    do: %{
      number: s.number,
      kind: s.kind,
      corrects: s.corrects,
      title: s.title,
      from_time: s.from_time,
      to_time: s.to_time
    }

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_day_not_witnessed
          )
        )
        |> halt()
  end
end
