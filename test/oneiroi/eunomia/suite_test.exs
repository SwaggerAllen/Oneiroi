defmodule Oneiroi.Eunomia.SuiteTest do
  @moduledoc "The regression aggregate, pure: numbers from its own counter, a card once, a grade once, a run once."
  use ExUnit.Case, async: true

  alias Commanded.Event.Upcaster
  alias Commanded.Serialization.JsonSerializer
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

    # A run ends once: failed or finished, never both, and an ended
    # run's deck takes no further card.
    fail = %Commands.FailRun{
      actor: @witness,
      at: @at,
      id: "r1",
      run_ref: "run1",
      reason: "eunomia_run_raised"
    }

    assert %Events.RunFailed{cards: 2, reason: "eunomia_run_raised"} = Suite.execute(s, fail)
    assert [] = Suite.execute(fold(s, [finish]), fail)
    failed = fold(s, [fail])
    assert [] = Suite.execute(failed, finish)
    assert [] = Suite.execute(failed, fail)
    assert [] = Suite.execute(failed, record("c3", "m2"))
    assert [] = Suite.execute(fold(s, [finish]), record("c3", "m2"))

    assert {:error, %{kind: :eunomia_no_such_run, site: :eunomia_fail_run_absent}} =
             Suite.execute(s, %{fail | run_ref: "nope"})
  end

  # A card recorded before the trace (eunomia #31) is a version 2 line
  # with no `trace` key; read through the store's own serializer, it
  # comes back with none and the upcaster gives it the empty trace.
  test "an AnswerRecorded of version 2, read from the log, upcasts to an empty trace" do
    v2 =
      Jason.encode!(%{
        actor: @witness,
        at: @at,
        id: "r1",
        run_ref: "run1",
        card_ref: "c1",
        model: "m1",
        test_number: 1,
        behaviour_number: nil,
        commitment_number: nil,
        content: "answer",
        refusal: false,
        failure: nil
      })

    type = Atom.to_string(Events.AnswerRecorded)
    read = JsonSerializer.deserialize(v2, type: type)
    assert %Events.AnswerRecorded{trace: nil, content: "answer"} = read

    assert %Events.AnswerRecorded{trace: [], content: "answer", card_ref: "c1"} =
             Upcaster.upcast(read, %{})

    # A version 3 line keeps its trace as written.
    step = %{
      "tool" => "trial_list",
      "arguments" => "{}",
      "kind" => "read",
      "result" => "Test #1",
      "truncated" => false
    }

    v3 = Suite.execute(fold(%Suite{}, [write(), start()]), %{record("c1") | trace: [step]})
    assert %Events.AnswerRecorded{trace: [^step]} = v3

    assert %Events.AnswerRecorded{trace: [%{tool: "trial_list", kind: "read", truncated: false}]} =
             v3
             |> JsonSerializer.serialize()
             |> JsonSerializer.deserialize(type: type)
             |> Upcaster.upcast(%{})

    # A command that names no trace records the empty one, never nil.
    assert %Events.AnswerRecorded{trace: []} =
             Suite.execute(fold(%Suite{}, [write(), start()]), record("c1"))
  end

  # The seal is held twice (eunomia #9): the export never reads the
  # regression stream, and every event on it declares itself out as
  # well. Each alone held the other's probe, so each has its own test:
  # this one, and the export's own in `Oneiroi.SimaQian.WholeTest`.
  test "every regression event, the card and its trace included, declares itself out of the export" do
    regression =
      for {module, _version} <- Oneiroi.Eunomia.events(),
          match?(["Oneiroi", "Eunomia", "Events", _event], Module.split(module)),
          do: module

    assert Enum.sort(regression) ==
             Enum.sort([
               Events.TestWritten,
               Events.TestChanged,
               Events.RunStarted,
               Events.AnswerRecorded,
               Events.RunFinished,
               Events.RunFailed,
               Events.AnswerGraded,
               Events.AnswerFavourited
             ])

    for module <- regression, do: refute(module.__export__?(), "#{inspect(module)} is exported")
  end
end
