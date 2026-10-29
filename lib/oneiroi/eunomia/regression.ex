defmodule Oneiroi.Eunomia.Regression do
  @moduledoc """
  Regression per resident, sealed (spec §6.4, F42): the command edge for
  tests, runs, grades and favourites; the run itself, every candidate
  answering every test in a sealed session; and the reads the Regression
  screen takes, cards blind until a test's are all graded.

  The sealed session is the brain's seed context (the prompt and the
  identity files, `Oneiroi.Brain.seed_context/1`) and the test's prompt,
  through the ledger under the `regression` purpose, which the resident's
  ledger view omits. Nothing of it is captured, nothing is written to the
  resident's stream, and no tool reads these rows.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Eunomia.Commands
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Router
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Eunomia.Suite
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.{Request, Result}
  alias Oneiroi.Scope

  # ---- tests ----

  def write_test(resident_id, %{prompt: p, passes_if: y, fails_if: n}, %Actor{} = actor) do
    command = %Commands.WriteTest{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      prompt: p,
      passes_if: y,
      fails_if: n
    }

    case dispatch(command) do
      {:ok, [%{number: number}]} -> {:ok, number}
      {:ok, _} -> {:error, Error.new(:eunomia_test_invalid)}
      other -> other
    end
  end

  def change_test(resident_id, number, %{prompt: p, passes_if: y, fails_if: n}, %Actor{} = actor) do
    command = %Commands.ChangeTest{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      prompt: p,
      passes_if: y,
      fails_if: n
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- runs ----

  @doc "Runs `models` against every test (or `tests`), synchronously; returns the run's ref."
  @spec run(String.t(), [String.t()], [pos_integer()] | :all, Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  def run(resident_id, models, tests \\ :all, %Actor{} = actor) when is_list(models) do
    models = models |> Enum.map(&to_string/1) |> Enum.uniq()
    numbers = if tests == :all, do: resident_id |> tests() |> Enum.map(& &1.number), else: tests

    with :ok <- bounded(models, numbers),
         ref = fresh_ref(),
         {:ok, _} <-
           dispatch(%Commands.StartRun{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             run_ref: ref,
             models: models,
             tests: numbers
           }) do
      context = Oneiroi.Brain.seed_context(resident_id)
      rows = resident_id |> tests() |> Map.new(&{&1.number, &1})

      for model <- models, number <- numbers do
        answer(resident_id, ref, model, Map.fetch!(rows, number), context, actor)
      end

      with {:ok, _} <-
             dispatch(%Commands.FinishRun{
               actor: actor,
               at: Clock.now(),
               id: resident_id,
               run_ref: ref
             }),
           do: {:ok, ref}
    end
  end

  defp answer(resident_id, ref, model, test, context, actor) do
    request = Request.new(model, context ++ [%{role: :user, content: test.prompt}])

    {content, refusal, failure} =
      case Nisaba.call(resident_id, :regression, request, actor) do
        {:ok, %Result{content: content, refusal?: refusal}} -> {content, refusal, nil}
        {:error, %{kind: kind}} when is_atom(kind) -> {nil, false, Atom.to_string(kind)}
        {:error, other} -> {nil, false, other |> inspect() |> String.slice(0, 200)}
      end

    dispatch(%Commands.RecordAnswer{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      run_ref: ref,
      card_ref: fresh_ref(),
      model: model,
      test_number: test.number,
      content: content,
      refusal: refusal,
      failure: failure
    })
  end

  def grade(resident_id, run_ref, card_ref, grade, %Actor{} = actor) do
    command = %Commands.GradeAnswer{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      run_ref: run_ref,
      card_ref: card_ref,
      grade: grade
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def favourite(resident_id, run_ref, card_ref, %Actor{} = actor) do
    command = %Commands.FavouriteAnswer{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      run_ref: run_ref,
      card_ref: card_ref
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  # ---- reads ----

  def tests(resident_id), do: Scope.resident(resident_id, fn -> Store.tests() end)

  def runs(resident_id), do: Scope.resident(resident_id, fn -> Store.runs() end)

  @doc """
  A run with its cards, blind: a card's `model` is nil until every card
  of its test is graded, and `results` ranks the models by pass rate over
  graded cards, with favourites counted, revealing only those tests.
  """
  def run_detail(resident_id, run_ref) do
    Scope.resident(resident_id, fn ->
      case Store.run(run_ref) do
        nil ->
          {:error, Error.new(:eunomia_no_such_run, ref: run_ref)}

        run ->
          answers = Store.answers(run_ref)
          revealed = revealed_tests(answers)
          cards = Enum.map(answers, &blind(&1, revealed))
          {:ok, run, cards, results(answers, revealed)}
      end
    end)
  end

  # Model names show only once every card in a test is graded (spec §6.4).
  defp revealed_tests(answers) do
    answers
    |> Enum.group_by(& &1.test_number)
    |> Enum.filter(fn {_n, cards} -> Enum.all?(cards, &(&1.grade != nil)) end)
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()
  end

  defp blind(a, revealed) do
    %{
      card_ref: a.card_ref,
      test_number: a.test_number,
      content: a.content,
      refusal: a.refusal,
      failure: a.failure,
      grade: a.grade,
      favourite: a.favourite,
      model: if(MapSet.member?(revealed, a.test_number), do: a.model, else: nil)
    }
  end

  defp results(answers, revealed) do
    answers
    |> Enum.filter(&MapSet.member?(revealed, &1.test_number))
    |> Enum.group_by(& &1.model)
    |> Enum.map(fn {model, cards} ->
      passed = Enum.count(cards, &(&1.grade == "pass"))

      %{
        model: model,
        graded: length(cards),
        passed: passed,
        pass_rate: Float.round(passed / length(cards), 3),
        favourites: Enum.count(cards, & &1.favourite)
      }
    end)
    |> Enum.sort_by(&{-&1.pass_rate, -&1.favourites, &1.model})
  end

  # ---- helpers ----

  defp bounded(models, numbers) do
    cond do
      models == [] or numbers == [] ->
        {:error, Error.new(:eunomia_run_empty)}

      length(models) > Config.fetch!(:eunomia, :run_models_max) ->
        {:error, Error.new(:eunomia_run_too_large, models: length(models))}

      length(numbers) > Config.fetch!(:eunomia, :run_tests_max) ->
        {:error, Error.new(:eunomia_run_too_large, tests: length(numbers))}

      true ->
        :ok
    end
  end

  defp fresh_ref, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :test_invalid} ->
        {:error, Error.new(:eunomia_test_invalid)}

      {:error, :no_such_test} ->
        {:error, Error.new(:eunomia_no_such_test)}

      {:error, :run_empty} ->
        {:error, Error.new(:eunomia_run_empty)}

      {:error, :no_such_run} ->
        {:error, Error.new(:eunomia_no_such_run, ref: command.run_ref)}

      {:error, :no_such_card} ->
        {:error, Error.new(:eunomia_no_such_card, ref: command.card_ref)}

      {:error, :grade_invalid} ->
        {:error, Error.new(:eunomia_grade_invalid, grades: Suite.grades())}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
