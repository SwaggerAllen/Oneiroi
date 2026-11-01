defmodule Oneiroi.Eunomia.SuiteTest do
  @moduledoc "The regression aggregate, pure: numbers from its own counter, a card once, a grade once, a run once."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Eunomia.Commands
  alias Oneiroi.Eunomia.Events
  alias Oneiroi.Eunomia.Suite

  @at ~U[2026-10-26 12:00:00Z]
  @witness Actor.new(:witness, "a1")

  defp fold(state, commands) do
    Enum.reduce(commands, state, fn c, s ->
      s |> Suite.execute(c) |> List.wrap() |> Enum.reduce(s, &Suite.apply(&2, &1))
    end)
  end

  defp write(prompt \\ "What do you do when I am late?") do
    %Commands.WriteTest{
      actor: @witness,
      at: @at,
      id: "r1",
      prompt: prompt,
      passes_if: "asks why, kindly",
      fails_if: "scolds"
    }
  end

  defp start(ref \\ "run1", models \\ ["m1", "m2"], tests \\ [1]),
    do: %Commands.StartRun{
      actor: @witness,
      at: @at,
      id: "r1",
      run_ref: ref,
      models: models,
      tests: tests
    }

  defp record(card, model \\ "m1", test \\ 1) do
    %Commands.RecordAnswer{
      actor: @witness,
      at: @at,
      id: "r1",
      run_ref: "run1",
      card_ref: card,
      model: model,
      test_number: test,
      content: "answer",
      refusal: false,
      failure: nil
    }
  end

  test "tests are numbered by the suite's own counter and each is three texts" do
    assert %Events.TestWritten{number: 1} = Suite.execute(%Suite{}, write())
    s = fold(%Suite{}, [write(), write("second")])
    assert %Events.TestWritten{number: 3} = Suite.execute(s, write("third"))

    assert {:error, %{kind: :eunomia_test_invalid, site: :eunomia_write_test_invalid}} =
             Suite.execute(%Suite{}, %{write() | fails_if: " "})

    assert {:error, %{kind: :eunomia_test_invalid, site: :eunomia_write_test_invalid}} =
             Suite.execute(%Suite{}, %{write() | prompt: String.duplicate("x", 4_001)})

    change = %Commands.ChangeTest{
      actor: @witness,
      at: @at,
      id: "r1",
      number: 1,
      prompt: "changed",
      passes_if: "y",
      fails_if: "n"
    }

    assert %Events.TestChanged{number: 1} = Suite.execute(s, change)
    assert [] = Suite.execute(fold(s, [change]), change)

    assert {:error, %{kind: :eunomia_no_such_test, site: :eunomia_change_test_absent}} =
             Suite.execute(s, %{change | number: 9})
  end

  test "a run is models x tests, cards land once, grades and favourites once, and it finishes once" do
    s = fold(%Suite{}, [write()])

    assert {:error, %{kind: :eunomia_run_empty, site: :eunomia_start_run_empty}} =
             Suite.execute(s, start("run1", [], [1]))

    assert {:error, %{kind: :eunomia_no_such_test, site: :eunomia_start_run_test_absent}} =
             Suite.execute(s, start("run1", ["m1"], [7]))

    assert %Events.RunStarted{models: ["m1", "m2"], tests: [1]} = Suite.execute(s, start())
    s = fold(s, [start()])
    assert [] = Suite.execute(s, start())

    assert {:error, %{kind: :eunomia_no_such_run, site: :eunomia_record_answer_run_absent}} =
             Suite.execute(s, %{record("c1") | run_ref: "nope"})

    assert %Events.AnswerRecorded{card_ref: "c1", model: "m1"} = Suite.execute(s, record("c1"))
    s = fold(s, [record("c1"), record("c2", "m2")])
    assert [] = Suite.execute(s, record("c1"))

    grade = %Commands.GradeAnswer{
      actor: @witness,
      at: @at,
      id: "r1",
      run_ref: "run1",
      card_ref: "c1",
      grade: "pass"
    }

    assert %Events.AnswerGraded{grade: "pass"} = Suite.execute(s, grade)
    assert [] = Suite.execute(fold(s, [grade]), grade)

    assert %Events.AnswerGraded{grade: "fail"} =
             Suite.execute(fold(s, [grade]), %{grade | grade: "fail"})

    assert {:error, %{kind: :eunomia_grade_invalid, site: :eunomia_grade_value_invalid}} =
             Suite.execute(s, %{grade | grade: "meh"})

    assert {:error, %{kind: :eunomia_no_such_card, site: :eunomia_card_absent}} =
             Suite.execute(s, %{grade | card_ref: "c9"})

    fav = %Commands.FavouriteAnswer{
      actor: @witness,
      at: @at,
      id: "r1",
      run_ref: "run1",
      card_ref: "c2"
    }

    assert %Events.AnswerFavourited{} = Suite.execute(s, fav)
    assert [] = Suite.execute(fold(s, [fav]), fav)

    finish = %Commands.FinishRun{actor: @witness, at: @at, id: "r1", run_ref: "run1"}
    assert %Events.RunFinished{cards: 2} = Suite.execute(s, finish)
    assert [] = Suite.execute(fold(s, [finish]), finish)
  end
end
