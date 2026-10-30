defmodule Oneiroi.Eunomia.Judgement do
  @moduledoc """
  The judgement aggregate on `judgement-<resident_id>` (spec §6.4).
  Pure: numbers, refs, instants and the judge's answer arrive on the
  command. It holds what its rules need: which positions exist and which
  are replaced (a chain cannot fork), which disputes are settled, which
  predictions resolved, which nights judged, and the judge's model.
  """

  alias Oneiroi.Eunomia.Events.Judgement, as: Events
  alias Oneiroi.Eunomia.JudgementCommands, as: Commands

  defstruct [
    :id,
    positions: %{},
    disputes: %{},
    predictions: %{},
    nights: MapSet.new(),
    audits: MapSet.new(),
    flags: %{},
    judge_model: nil
  ]

  @statement_limit 1_000
  @sources ~w(live night)
  @check_outcomes ~w(advised timed_out)
  @advices ~w(concede hold unclear)
  @settlements ~w(conceded held)
  @resolutions ~w(right wrong void)

  @doc "What a dispute settles as."
  def settlements, do: @settlements
  @doc "What a prediction resolves as."
  def resolutions, do: @resolutions
  @doc "What the judge may advise."
  def advices, do: @advices

  # ---- positions ----

  def execute(%__MODULE__{positions: positions}, %Commands.TakePosition{} = c) do
    cond do
      Map.has_key?(positions, c.number) ->
        []

      not statement_ok?(c.statement) ->
        {:error, :statement_invalid}

      true ->
        %Events.PositionTaken{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          statement: c.statement,
          session_key: c.session_key,
          turn_ref: c.turn_ref
        }
    end
  end

  # A chain cannot fork (spec §3.2): the position replaced must be the
  # head of its chain.
  def execute(%__MODULE__{positions: positions}, %Commands.ReplacePosition{} = c) do
    cond do
      Map.has_key?(positions, c.number) ->
        []

      not Map.has_key?(positions, c.replaces) ->
        {:error, :no_such_position}

      positions[c.replaces].replaced_by != nil ->
        {:error, :position_replaced}

      not statement_ok?(c.statement) ->
        {:error, :statement_invalid}

      true ->
        %Events.PositionReplaced{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          replaces: c.replaces,
          statement: c.statement,
          session_key: c.session_key,
          turn_ref: c.turn_ref
        }
    end
  end

  # ---- disputes ----

  def execute(%__MODULE__{} = s, %Commands.CheckDispute{} = c) do
    cond do
      Map.has_key?(s.disputes, c.ref) ->
        []

      c.source not in @sources or c.outcome not in @check_outcomes ->
        {:error, :dispute_invalid}

      not (is_nil(c.advice) or c.advice in @advices) ->
        {:error, :dispute_invalid}

      not (is_nil(c.position_number) or Map.has_key?(s.positions, c.position_number)) ->
        {:error, :no_such_position}

      true ->
        %Events.DisputeChecked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          ref: c.ref,
          source: c.source,
          position_number: c.position_number,
          claim: c.claim,
          stance: c.stance,
          session_key: c.session_key,
          turn_ref: c.turn_ref,
          outcome: c.outcome,
          advice: c.advice,
          advice_text: c.advice_text,
          judge_model: c.judge_model,
          criteria: c.criteria
        }
    end
  end

  def execute(%__MODULE__{disputes: disputes}, %Commands.SettleDispute{} = c) do
    case Map.get(disputes, c.ref) do
      nil ->
        {:error, :no_such_dispute}

      %{settled: true} ->
        []

      _open ->
        if c.outcome in @settlements,
          do: %Events.DisputeSettled{
            actor: c.actor,
            at: c.at,
            note: c.note,
            id: c.id,
            ref: c.ref,
            outcome: c.outcome
          },
          else: {:error, :settlement_invalid}
    end
  end

  # ---- nights ----

  def execute(%__MODULE__{nights: nights}, %Commands.RecordNight{} = c) do
    if MapSet.member?(nights, c.day),
      do: [],
      else: %Events.NightJudged{
        actor: c.actor,
        at: c.at,
        id: c.id,
        day: c.day,
        messages: c.messages,
        chars: c.chars,
        found: c.found,
        judge_model: c.judge_model,
        summary: c.summary,
        criteria: c.criteria
      }
  end

  def execute(%__MODULE__{nights: nights}, %Commands.FailNight{} = c) do
    if MapSet.member?(nights, c.day),
      do: [],
      else: %Events.NightFailed{actor: c.actor, at: c.at, id: c.id, day: c.day, reason: c.reason}
  end

  # ---- predictions ----

  def execute(%__MODULE__{predictions: predictions}, %Commands.LogPrediction{} = c) do
    cond do
      Map.has_key?(predictions, c.number) ->
        []

      not statement_ok?(c.statement) ->
        {:error, :statement_invalid}

      not match?(%DateTime{}, c.due) ->
        {:error, :due_invalid}

      true ->
        %Events.PredictionLogged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          statement: c.statement,
          due: c.due,
          session_key: c.session_key,
          turn_ref: c.turn_ref
        }
    end
  end

  def execute(%__MODULE__{predictions: predictions}, %Commands.ResolvePrediction{} = c) do
    case Map.get(predictions, c.number) do
      nil ->
        {:error, :no_such_prediction}

      %{resolved: true} ->
        []

      _open ->
        if c.outcome in @resolutions,
          do: %Events.PredictionResolved{
            actor: c.actor,
            at: c.at,
            note: c.note,
            id: c.id,
            number: c.number,
            outcome: c.outcome
          },
          else: {:error, :resolution_invalid}
    end
  end

  # ---- the weekly memory audit ----

  def execute(%__MODULE__{audits: audits}, %Commands.RunAudit{} = c) do
    if MapSet.member?(audits, c.ref),
      do: [],
      else: %Events.AuditRun{
        actor: c.actor,
        at: c.at,
        id: c.id,
        ref: c.ref,
        conclusions: c.conclusions,
        flagged: c.flagged,
        judge_model: c.judge_model,
        summary: c.summary,
        criteria: c.criteria
      }
  end

  def execute(%__MODULE__{}, %Commands.FailAudit{} = c),
    do: %Events.AuditFailed{actor: c.actor, at: c.at, id: c.id, ref: c.ref, reason: c.reason}

  def execute(%__MODULE__{flags: flags}, %Commands.RaiseAuditFlag{} = c) do
    if Map.has_key?(flags, c.ref),
      do: [],
      else: %Events.AuditFlagRaised{
        actor: c.actor,
        at: c.at,
        id: c.id,
        ref: c.ref,
        audit_ref: c.audit_ref,
        conclusion_id: c.conclusion_id,
        conclusion: c.conclusion,
        reason: c.reason
      }
  end

  def execute(%__MODULE__{flags: flags}, %Commands.ApproveAuditFlag{} = c) do
    case Map.get(flags, c.ref) do
      nil ->
        {:error, :no_such_flag}

      %{decided: true} ->
        []

      _open ->
        %Events.AuditFlagApproved{actor: c.actor, at: c.at, note: c.note, id: c.id, ref: c.ref}
    end
  end

  def execute(%__MODULE__{flags: flags}, %Commands.DeleteAuditFlag{} = c) do
    case Map.get(flags, c.ref) do
      nil ->
        {:error, :no_such_flag}

      %{decided: true} ->
        []

      _open ->
        %Events.AuditFlagDeleted{actor: c.actor, at: c.at, note: c.note, id: c.id, ref: c.ref}
    end
  end

  # ---- the judge ----

  def execute(%__MODULE__{judge_model: current}, %Commands.SetJudgeModel{} = c) do
    cond do
      current == c.model ->
        []

      not model_ok?(c.model) ->
        {:error, :judge_model_invalid}

      true ->
        %Events.JudgeModelChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          model: c.model,
          previous: current
        }
    end
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.PositionTaken{} = e) do
    %{s | id: e.id, positions: Map.put(s.positions, e.number, %{replaced_by: nil})}
  end

  def apply(%__MODULE__{} = s, %Events.PositionReplaced{} = e) do
    s = put_in(s.positions[e.replaces].replaced_by, e.number)
    %{s | positions: Map.put(s.positions, e.number, %{replaced_by: nil})}
  end

  def apply(%__MODULE__{} = s, %Events.DisputeChecked{} = e),
    do: %{s | id: e.id, disputes: Map.put(s.disputes, e.ref, %{settled: false})}

  def apply(%__MODULE__{} = s, %Events.DisputeSettled{} = e),
    do: put_in(s.disputes[e.ref].settled, true)

  def apply(%__MODULE__{} = s, %Events.NightJudged{} = e),
    do: %{s | id: e.id, nights: MapSet.put(s.nights, e.day)}

  def apply(%__MODULE__{} = s, %Events.NightFailed{}), do: s

  def apply(%__MODULE__{} = s, %Events.PredictionLogged{} = e),
    do: %{s | id: e.id, predictions: Map.put(s.predictions, e.number, %{resolved: false})}

  def apply(%__MODULE__{} = s, %Events.PredictionResolved{} = e),
    do: put_in(s.predictions[e.number].resolved, true)

  def apply(%__MODULE__{} = s, %Events.AuditRun{} = e),
    do: %{s | id: e.id, audits: MapSet.put(s.audits, e.ref)}

  def apply(%__MODULE__{} = s, %Events.AuditFailed{}), do: s

  def apply(%__MODULE__{} = s, %Events.AuditFlagRaised{} = e),
    do: %{s | flags: Map.put(s.flags, e.ref, %{decided: false})}

  def apply(%__MODULE__{} = s, %Events.AuditFlagApproved{} = e),
    do: put_in(s.flags[e.ref].decided, true)

  def apply(%__MODULE__{} = s, %Events.AuditFlagDeleted{} = e),
    do: put_in(s.flags[e.ref].decided, true)

  def apply(%__MODULE__{} = s, %Events.JudgeModelChanged{} = e),
    do: %{s | id: e.id, judge_model: e.model}

  # ---- helpers ----

  defp statement_ok?(text),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= @statement_limit

  defp model_ok?(model), do: is_binary(model) and String.trim(model) != ""
end
