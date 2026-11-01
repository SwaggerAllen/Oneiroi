defmodule Oneiroi.Eunomia.Projectors.Regression do
  @moduledoc "Folds the regression streams into tests, runs and cards."
  use Oneiroi.Projection, name: "eunomia_regression"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Eunomia.Events
  alias Oneiroi.Eunomia.Store.{Answer, Run, Test}

  fold(%Events.TestWritten{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :test,
      %Test{
        resident_id: e.id,
        number: e.number,
        prompt: e.prompt,
        passes_if: e.passes_if,
        fails_if: e.fails_if,
        written_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.TestChanged{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :test,
      from(t in Test, where: t.resident_id == ^e.id and t.number == ^e.number),
      set: [prompt: e.prompt, passes_if: e.passes_if, fails_if: e.fails_if, changed_at: e.at]
    )
  end)

  fold(%Events.RunStarted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :run,
      %Run{
        resident_id: e.id,
        ref: e.run_ref,
        models: e.models,
        tests: e.tests,
        behaviours: e.behaviours || [],
        commitments: e.commitments || [],
        started_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.AnswerRecorded{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :answer,
      %Answer{
        resident_id: e.id,
        run_ref: e.run_ref,
        card_ref: e.card_ref,
        model: e.model,
        test_number: e.test_number,
        behaviour_number: e.behaviour_number,
        commitment_number: e.commitment_number,
        content: e.content,
        refusal: e.refusal == true,
        failure: e.failure,
        recorded_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :run_ref, :card_ref]
    )
    |> Multi.update_all(
      :cards,
      from(r in Run, where: r.resident_id == ^e.id and r.ref == ^e.run_ref),
      inc: [cards: 1]
    )
  end)

  fold(%Events.RunFinished{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :run,
      from(r in Run, where: r.resident_id == ^e.id and r.ref == ^e.run_ref),
      set: [finished_at: e.at, cards: e.cards]
    )
  end)

  fold(%Events.RunFailed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :run,
      from(r in Run, where: r.resident_id == ^e.id and r.ref == ^e.run_ref),
      set: [failed_at: e.at, failure: e.reason, cards: e.cards]
    )
  end)

  fold(%Events.AnswerGraded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :graded,
      from(a in Answer,
        where: a.resident_id == ^e.id and a.run_ref == ^e.run_ref and a.card_ref == ^e.card_ref
      ),
      set: [grade: e.grade, graded_at: e.at]
    )
  end)

  fold(%Events.AnswerFavourited{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :favourite,
      from(a in Answer,
        where: a.resident_id == ^e.id and a.run_ref == ^e.run_ref and a.card_ref == ^e.card_ref
      ),
      set: [favourite: true]
    )
  end)
end
