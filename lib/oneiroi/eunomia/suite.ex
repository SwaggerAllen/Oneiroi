defmodule Oneiroi.Eunomia.Suite do
  @moduledoc """
  The regression suite aggregate on `regression-<resident_id>` (spec
  §6.4). Pure: refs and instants arrive on the command; the test number
  is its own counter.

  It holds what its rules need: the tests by number, and each run's
  cards with their grade and favourite, so a grade lands once, a card
  is one of the run's, and a run finishes when every card is recorded.
  """

  alias Oneiroi.Eunomia.Commands
  alias Oneiroi.Eunomia.Events

  defstruct [:id, tests: %{}, next_test: 1, runs: %{}]

  @grades ~w(pass fail)
  # Bounds on the texts: a test is read on a card by a thumb (spec §10).
  @text_limit 4_000

  @doc "The grades a card takes."
  @spec grades() :: [String.t()]
  def grades, do: @grades

  # ---- execute ----

  def execute(%__MODULE__{} = s, %Commands.WriteTest{} = c) do
    if texts_ok?(c) do
      %Events.TestWritten{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: s.next_test,
        prompt: c.prompt,
        passes_if: c.passes_if,
        fails_if: c.fails_if
      }
    else
      {:error, :test_invalid}
    end
  end

  def execute(%__MODULE__{tests: tests}, %Commands.ChangeTest{} = c) do
    cond do
      not Map.has_key?(tests, c.number) ->
        {:error, :no_such_test}

      not texts_ok?(c) ->
        {:error, :test_invalid}

      Map.get(tests, c.number) == texts(c) ->
        []

      true ->
        %Events.TestChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          prompt: c.prompt,
          passes_if: c.passes_if,
          fails_if: c.fails_if
        }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.StartRun{} = c) do
    cond do
      Map.has_key?(s.runs, c.run_ref) ->
        []

      c.models == [] or (c.tests == [] and List.wrap(c.behaviours) == []) ->
        {:error, :run_empty}

      Enum.any?(c.tests, &(not Map.has_key?(s.tests, &1))) ->
        {:error, :no_such_test}

      true ->
        %Events.RunStarted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          run_ref: c.run_ref,
          models: c.models,
          tests: c.tests,
          behaviours: List.wrap(c.behaviours)
        }
    end
  end

  def execute(%__MODULE__{runs: runs}, %Commands.RecordAnswer{} = c) do
    case Map.get(runs, c.run_ref) do
      nil ->
        {:error, :no_such_run}

      %{cards: cards} when is_map_key(cards, c.card_ref) ->
        []

      _run ->
        %Events.AnswerRecorded{
          actor: c.actor,
          at: c.at,
          id: c.id,
          run_ref: c.run_ref,
          card_ref: c.card_ref,
          model: c.model,
          test_number: c.test_number,
          behaviour_number: c.behaviour_number,
          content: c.content,
          refusal: c.refusal == true,
          failure: c.failure
        }
    end
  end

  def execute(%__MODULE__{runs: runs}, %Commands.FinishRun{} = c) do
    case Map.get(runs, c.run_ref) do
      nil ->
        {:error, :no_such_run}

      %{finished: true} ->
        []

      %{cards: cards} ->
        %Events.RunFinished{
          actor: c.actor,
          at: c.at,
          id: c.id,
          run_ref: c.run_ref,
          cards: map_size(cards)
        }
    end
  end

  def execute(%__MODULE__{runs: runs}, %Commands.GradeAnswer{} = c) do
    with {:ok, card} <- card(runs, c.run_ref, c.card_ref),
         :ok <- grade_ok(c.grade) do
      if card.grade == c.grade,
        do: [],
        else: %Events.AnswerGraded{
          actor: c.actor,
          at: c.at,
          id: c.id,
          run_ref: c.run_ref,
          card_ref: c.card_ref,
          grade: c.grade
        }
    end
  end

  def execute(%__MODULE__{runs: runs}, %Commands.FavouriteAnswer{} = c) do
    with {:ok, card} <- card(runs, c.run_ref, c.card_ref) do
      if card.favourite,
        do: [],
        else: %Events.AnswerFavourited{
          actor: c.actor,
          at: c.at,
          id: c.id,
          run_ref: c.run_ref,
          card_ref: c.card_ref
        }
    end
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.TestWritten{} = e) do
    %{
      s
      | id: e.id,
        tests: Map.put(s.tests, e.number, texts(e)),
        next_test: max(s.next_test, e.number + 1)
    }
  end

  def apply(%__MODULE__{} = s, %Events.TestChanged{} = e),
    do: %{s | tests: Map.put(s.tests, e.number, texts(e))}

  def apply(%__MODULE__{} = s, %Events.RunStarted{} = e),
    do: %{s | id: e.id, runs: Map.put(s.runs, e.run_ref, %{cards: %{}, finished: false})}

  def apply(%__MODULE__{} = s, %Events.AnswerRecorded{} = e) do
    card = %{
      model: e.model,
      trial: {e.test_number, e.behaviour_number},
      grade: nil,
      favourite: false
    }

    put_in(s.runs[e.run_ref].cards[e.card_ref], card)
  end

  def apply(%__MODULE__{} = s, %Events.RunFinished{} = e),
    do: put_in(s.runs[e.run_ref].finished, true)

  def apply(%__MODULE__{} = s, %Events.AnswerGraded{} = e),
    do: put_in(s.runs[e.run_ref].cards[e.card_ref].grade, e.grade)

  def apply(%__MODULE__{} = s, %Events.AnswerFavourited{} = e),
    do: put_in(s.runs[e.run_ref].cards[e.card_ref].favourite, true)

  # ---- helpers ----

  defp texts(c), do: %{prompt: c.prompt, passes_if: c.passes_if, fails_if: c.fails_if}

  defp texts_ok?(c),
    do: Enum.all?([c.prompt, c.passes_if, c.fails_if], &text_ok?/1)

  defp text_ok?(t),
    do: is_binary(t) and String.trim(t) != "" and String.length(t) <= @text_limit

  defp grade_ok(grade) when grade in @grades, do: :ok
  defp grade_ok(_other), do: {:error, :grade_invalid}

  defp card(runs, run_ref, card_ref) do
    case Map.get(runs, run_ref) do
      nil -> {:error, :no_such_run}
      %{cards: cards} -> with :error <- Map.fetch(cards, card_ref), do: {:error, :no_such_card}
    end
  end
end
