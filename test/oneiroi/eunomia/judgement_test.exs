defmodule Oneiroi.Eunomia.JudgementTest do
  @moduledoc "The judgement aggregate, pure: chains that cannot fork, a dispute settled once, a night judged once, a prediction resolved once."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Eunomia.Events.Judgement, as: Events
  alias Oneiroi.Eunomia.Judgement
  alias Oneiroi.Eunomia.JudgementCommands, as: Commands

  @actor Actor.new(:resident, "r", "fake/model")
  @at ~U[2026-10-26 12:00:00.000000Z]

  defp evolve(state \\ %Judgement{}, events),
    do: Enum.reduce(List.wrap(events), state, &Judgement.apply(&2, &1))

  defp cmd(module, fields),
    do: struct!(module, Map.merge(%{actor: @actor, at: @at, id: "r"}, Map.new(fields)))

  test "a chain cannot fork: only the head of a chain is replaced, and a taken number is taken once" do
    take = cmd(Commands.TakePosition, number: 1, statement: "Tea before coffee.")
    assert %Events.PositionTaken{number: 1} = Judgement.execute(%Judgement{}, take)
    s = evolve(Judgement.execute(%Judgement{}, take))
    assert [] = Judgement.execute(s, take)

    assert {:error, :statement_invalid} =
             Judgement.execute(s, cmd(Commands.TakePosition, number: 2, statement: "   "))

    replace =
      cmd(Commands.ReplacePosition, number: 2, replaces: 1, statement: "Coffee, actually.")

    assert %Events.PositionReplaced{number: 2, replaces: 1} = Judgement.execute(s, replace)
    s = evolve(s, Judgement.execute(s, replace))

    assert {:error, :position_replaced} =
             Judgement.execute(
               s,
               cmd(Commands.ReplacePosition, number: 3, replaces: 1, statement: "Neither.")
             )

    assert %Events.PositionReplaced{replaces: 2} =
             Judgement.execute(
               s,
               cmd(Commands.ReplacePosition, number: 3, replaces: 2, statement: "Neither.")
             )

    assert {:error, :no_such_position} =
             Judgement.execute(
               s,
               cmd(Commands.ReplacePosition, number: 3, replaces: 9, statement: "Neither.")
             )
  end

  test "a dispute is checked once and settled once, in the closed vocabularies" do
    check =
      cmd(Commands.CheckDispute,
        ref: "d1",
        source: "live",
        position_number: nil,
        claim: "it rained",
        stance: "it did not",
        outcome: "advised",
        advice: "concede",
        advice_text: "ADVICE: concede",
        judge_model: "fake/judge"
      )

    assert %Events.DisputeChecked{ref: "d1", advice: "concede"} =
             Judgement.execute(%Judgement{}, check)

    s = evolve(Judgement.execute(%Judgement{}, check))
    assert [] = Judgement.execute(s, check)

    assert {:error, :dispute_invalid} =
             Judgement.execute(%Judgement{}, %{check | ref: "d2", outcome: "judged"})

    assert {:error, :dispute_invalid} =
             Judgement.execute(%Judgement{}, %{check | ref: "d2", advice: "maybe"})

    assert {:error, :no_such_position} =
             Judgement.execute(%Judgement{}, %{check | ref: "d2", position_number: 7})

    settle = cmd(Commands.SettleDispute, ref: "d1", outcome: "conceded", note: "fair")

    assert %Events.DisputeSettled{outcome: "conceded", note: "fair"} =
             Judgement.execute(s, settle)

    s = evolve(s, Judgement.execute(s, settle))
    assert [] = Judgement.execute(s, %{settle | outcome: "held"})

    assert {:error, :settlement_invalid} =
             Judgement.execute(
               evolve(Judgement.execute(%Judgement{}, %{check | ref: "d3"})),
               %{settle | ref: "d3", outcome: "won"}
             )

    assert {:error, :no_such_dispute} = Judgement.execute(s, %{settle | ref: "zz"})
  end

  test "a night is judged once, a failed night may run again, and the judge is set once per model" do
    night =
      cmd(Commands.RecordNight,
        day: "2026-10-25",
        messages: 3,
        chars: 40,
        found: 1,
        judge_model: "fake/judge",
        summary: "quiet"
      )

    s = evolve(Judgement.execute(%Judgement{}, night))
    assert [] = Judgement.execute(s, night)
    assert [] = Judgement.execute(s, cmd(Commands.FailNight, day: "2026-10-25", reason: "x"))

    fail = cmd(Commands.FailNight, day: "2026-10-24", reason: "named [9]")
    assert %Events.NightFailed{} = Judgement.execute(s, fail)
    s = evolve(s, Judgement.execute(s, fail))

    assert %Events.NightJudged{day: "2026-10-24"} =
             Judgement.execute(s, %{night | day: "2026-10-24"})

    set = cmd(Commands.SetJudgeModel, model: "fake/judge2")

    assert %Events.JudgeModelChanged{model: "fake/judge2", previous: nil} =
             Judgement.execute(s, set)

    s = evolve(s, Judgement.execute(s, set))
    assert [] = Judgement.execute(s, set)
    assert {:error, :judge_model_invalid} = Judgement.execute(s, %{set | model: " "})
  end

  test "a prediction is logged with a due instant and resolved once, right, wrong or void" do
    log = cmd(Commands.LogPrediction, number: 1, statement: "It will rain Friday.", due: @at)
    assert %Events.PredictionLogged{number: 1} = Judgement.execute(%Judgement{}, log)
    assert {:error, :due_invalid} = Judgement.execute(%Judgement{}, %{log | due: "Friday"})
    s = evolve(Judgement.execute(%Judgement{}, log))
    assert [] = Judgement.execute(s, log)

    resolve = cmd(Commands.ResolvePrediction, number: 1, outcome: "right", note: "it poured")
    assert %Events.PredictionResolved{outcome: "right"} = Judgement.execute(s, resolve)
    s = evolve(s, Judgement.execute(s, resolve))
    assert [] = Judgement.execute(s, %{resolve | outcome: "wrong"})
    assert {:error, :no_such_prediction} = Judgement.execute(s, %{resolve | number: 2})

    assert {:error, :resolution_invalid} =
             Judgement.execute(
               evolve(Judgement.execute(%Judgement{}, %{log | number: 2})),
               %{resolve | number: 2, outcome: "maybe"}
             )
  end
end
