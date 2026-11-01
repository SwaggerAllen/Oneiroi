defmodule OneiroiWeb.JudgementController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Eunomia
  alias OpenApiSpex.Schema

  tags(["judgement"])

  plug(:witnessed)

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
    do:
      problem(
        conn,
        422,
        :note_required,
        :web_judgement_resolve_note_required,
        "outcome and note are required"
      )

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

  operation(:audits,
    summary: "The weekly memory audits and their flags, open first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"audits", "application/json", %Schema{type: :object}}]
  )

  def audits(conn, %{"id" => id}) do
    a = Eunomia.audits(id)

    json(conn, %{
      runs: Enum.map(a.runs, &audit/1),
      open: Enum.map(a.open, &flag/1),
      decided: Enum.map(a.decided, &flag/1)
    })
  end

  operation(:run_audit,
    summary: "Run the weekly memory audit by hand",
    parameters: [id: [in: :path, type: :string]],
    responses: [created: {"the audit's ref", "application/json", %Schema{type: :object}}]
  )

  operation(:washes,
    summary:
      "The wash pass's runs and flags, open first (spec §6.13, P18): the witness reads, the resident decides",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the wash", "application/json", %Schema{type: :object}}]
  )

  def washes(conn, %{"id" => id}) do
    w = Eunomia.washes(id)

    json(conn, %{
      runs: Enum.map(w.runs, &wash/1),
      open: Enum.map(w.open, &wash_flag/1),
      decided: Enum.map(w.decided, &wash_flag/1)
    })
  end

  operation(:run_wash,
    summary: "Run the wash pass now, as the weekly job would",
    parameters: [id: [in: :path, type: :string]],
    responses: [created: {"the run's ref", "application/json", %Schema{type: :object}}]
  )

  def run_wash(conn, %{"id" => id}) do
    case Eunomia.run_wash(id, actor(conn)) do
      {:ok, ref} -> conn |> put_status(201) |> json(%{ref: ref})
      other -> respond(conn, other)
    end
  end

  def run_audit(conn, %{"id" => id}) do
    case Eunomia.run_audit(id, actor(conn)) do
      {:ok, ref} -> conn |> put_status(201) |> json(%{ref: ref})
      other -> respond(conn, other)
    end
  end

  operation(:decide_flag,
    summary:
      "Approve a flag (the conclusion is deleted from Honcho) or delete it (the conclusion stays), with a note",
    parameters: [id: [in: :path, type: :string], ref: [in: :path, type: :string]],
    request_body:
      {"the decision", "application/json",
       %Schema{
         type: :object,
         required: [:decision, :note],
         properties: %{
           decision: %Schema{type: :string, enum: ~w(approve delete)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "decided"]
  )

  def decide_flag(conn, %{"id" => id, "ref" => ref, "decision" => "approve", "note" => note}),
    do: respond(conn, Eunomia.approve_flag(id, ref, note, actor(conn)))

  def decide_flag(conn, %{"id" => id, "ref" => ref, "decision" => "delete", "note" => note}),
    do: respond(conn, Eunomia.delete_flag(id, ref, note, actor(conn)))

  def decide_flag(conn, _params),
    do:
      problem(
        conn,
        422,
        :decision_required,
        :web_judgement_decide_flag_decision_required,
        "decision (approve or delete) and note are required"
      )

  # ---- shapes ----

  defp wash(w) do
    %{
      ref: w.ref,
      outcome: w.outcome,
      entries: w.entries,
      flagged: w.flagged,
      judge_model: w.judge_model,
      summary: w.summary,
      reason: w.reason,
      at: w.at
    }
  end

  defp wash_flag(f) do
    %{
      ref: f.ref,
      wash_ref: f.wash_ref,
      file: f.file,
      entry: f.entry,
      kind: f.kind,
      reason: f.reason,
      raised_at: f.raised_at,
      decision: f.decision,
      note: f.note,
      decided_at: f.decided_at
    }
  end

  defp audit(a) do
    %{
      ref: a.ref,
      outcome: a.outcome,
      conclusions: a.conclusions,
      flagged: a.flagged,
      judge_model: a.judge_model,
      summary: a.summary,
      reason: a.reason,
      at: a.at
    }
  end

  defp flag(f) do
    %{
      ref: f.ref,
      audit_ref: f.audit_ref,
      conclusion: f.conclusion,
      reason: f.reason,
      raised_at: f.raised_at,
      decision: f.decision,
      note: f.note,
      decided_at: f.decided_at
    }
  end

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
      movements: n.movements,
      reason: n.reason
    }
  end

  # Every route here is a resident's, read or written by its witness.
  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_judgement_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [
              :eunomia_no_such_prediction,
              :eunomia_no_such_position,
              :eunomia_no_such_dispute,
              :eunomia_no_such_flag
            ],
       do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)

  defp respond(conn, {:error, reason}),
    do: problem(conn, 422, :refused, :web_judgement_respond_refused, inspect(reason))

  defp integer(n) when is_integer(n), do: n

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _other -> 0
    end
  end
end
