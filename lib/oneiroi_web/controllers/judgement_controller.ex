defmodule OneiroiWeb.JudgementController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Eunomia
  alias OpenApiSpex.Schema

  tags(["judgement"])

  plug(:stewarded)

  operation(:show,
    summary:
      "The judge, its changes, and the concession ratio by week with earned concessions counted",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"judgement", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}) do
    j = Eunomia.judgement(id)

    json(conn, %{
      judge_model: j.judge_model,
      chosen: j.chosen,
      default: j.default,
      changes: Enum.map(j.changes, &%{model: &1.model, previous: &1.previous, at: &1.at}),
      weeks: j.weeks
    })
  end

  operation(:set_judge,
    summary: "Choose the judge's model; the resident's own chat model is refused",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the judge", "application/json",
       %Schema{type: :object, required: [:model], properties: %{model: %Schema{type: :string}}}},
    responses: [no_content: "chosen"]
  )

  def set_judge(conn, %{"id" => id} = params),
    do: respond(conn, Eunomia.set_judge_model(id, params["model"], actor(conn)))

  operation(:positions,
    summary: "Every position with its chain",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"positions", "application/json", %Schema{type: :array}}]
  )

  def positions(conn, %{"id" => id}),
    do: json(conn, id |> Eunomia.positions() |> Enum.map(&position/1))

  operation(:disputes,
    summary: "The disputes, live and nightly, with advice, outcome and the judge's model",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"disputes", "application/json", %Schema{type: :array}}]
  )

  def disputes(conn, %{"id" => id}),
    do: json(conn, id |> Eunomia.disputes() |> Enum.map(&dispute/1))

  operation(:predictions,
    summary: "Predictions: open soonest first, resolved with tallies",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"predictions", "application/json", %Schema{type: :object}}]
  )

  def predictions(conn, %{"id" => id}) do
    p = Eunomia.predictions(id)

    json(conn, %{
      open: Enum.map(p.open, &prediction/1),
      resolved: Enum.map(p.resolved, &prediction/1),
      tally: p.tally
    })
  end

  operation(:resolve,
    summary: "Resolve a prediction right, wrong or void, with a note",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the resolution", "application/json",
       %Schema{
         type: :object,
         required: [:outcome, :note],
         properties: %{
           outcome: %Schema{type: :string, enum: ~w(right wrong void)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "resolved"]
  )

  def resolve(conn, %{"id" => id, "number" => number, "outcome" => outcome, "note" => note}),
    do: respond(conn, Eunomia.resolve_prediction(id, integer(number), outcome, note, actor(conn)))

  def resolve(conn, _params),
    do: problem(conn, 422, :note_required, "outcome and note are required")

  operation(:nights,
    summary: "The nightly passes, newest first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"nights", "application/json", %Schema{type: :array}}]
  )

  def nights(conn, %{"id" => id}), do: json(conn, id |> Eunomia.nights() |> Enum.map(&night/1))

  operation(:judge_night,
    summary: "Run the nightly pass for a day by hand; once per day",
    parameters: [id: [in: :path, type: :string], day: [in: :path, type: :string]],
    responses: [
      no_content: "judged",
      ok: {"already judged", "application/json", %Schema{type: :object}}
    ]
  )

  def judge_night(conn, %{"id" => id, "day" => day}) do
    case Eunomia.judge_night(id, day, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      :already -> json(conn, %{already: true})
      other -> respond(conn, other)
    end
  end

  # ---- shapes ----

  defp position(p) do
    %{
      number: p.number,
      statement: p.statement,
      session_key: p.session_key,
      turn_ref: p.turn_ref,
      replaces: p.replaces,
      replaced_by: p.replaced_by,
      taken_at: p.taken_at,
      replaced_at: p.replaced_at
    }
  end

  defp dispute(d) do
    %{
      ref: d.ref,
      source: d.source,
      position_number: d.position_number,
      claim: d.claim,
      stance: d.stance,
      session_key: d.session_key,
      turn_ref: d.turn_ref,
      outcome: d.outcome,
      advice: d.advice,
      advice_text: d.advice_text,
      judge_model: d.judge_model,
      checked_at: d.checked_at,
      settlement: d.settlement,
      settled_note: d.settled_note,
      settled_by: d.settled_by_kind,
      settled_at: d.settled_at
    }
  end

  defp prediction(p) do
    %{
      number: p.number,
      statement: p.statement,
      due: p.due,
      logged_at: p.logged_at,
      outcome: p.outcome,
      note: p.note,
      resolved_at: p.resolved_at
    }
  end

  defp night(n) do
    %{
      day: n.day,
      at: n.at,
      outcome: n.outcome,
      messages: n.messages,
      chars: n.chars,
      found: n.found,
      judge_model: n.judge_model,
      summary: n.summary,
      reason: n.reason
    }
  end

  # Every route here is a resident's, read or written by its steward.
  defp stewarded(%{params: %{"id" => id}} = conn, _opts) do
    if stewards?(conn, id),
      do: conn,
      else: conn |> error(404, ResidentError.new(:agathos_daimon_not_stewarded)) |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [
              :eunomia_no_such_prediction,
              :eunomia_no_such_position,
              :eunomia_no_such_dispute
            ],
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
