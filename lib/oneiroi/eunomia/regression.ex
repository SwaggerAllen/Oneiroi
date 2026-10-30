defmodule Oneiroi.Eunomia.Regression do
  @moduledoc """
  Regression per resident, sealed (spec §6.4, F42): the command edge for
  tests, runs, grades and favourites; the run itself, every candidate
  answering every test in a sealed session; and the reads the Regression
  screen takes, cards blind until a test's are all graded.

  The sealed session is the seed context (`seed_context/1`: the brain's
  prompt file and the identity files, nothing of memory) and the trial's
  prompt, through the ledger under the `regression` purpose, which the
  resident's ledger view omits. Nothing of it is captured, nothing is
  written to the resident's stream, and no tool reads these rows.

  Trials are the authored tests and, when asked, those derived from
  behaviours (spec §6.4): a behaviour's trigger is the situation, its
  enactment what passes, its absence what fails. The derivation happens
  here, inside the sealed session, and nothing of it reaches memory.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Eunomia.Commands
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Router
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Eunomia.Suite
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
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

  @doc """
  Runs `models` against the trials, synchronously; returns the run's ref.
  `selection` is `:all` (every test, no behaviours), a list of test
  numbers, or `%{tests: :all | [n], behaviours: :all | [n]}`.
  """
  @spec run(String.t(), [String.t()], term(), Actor.t()) :: {:ok, String.t()} | {:error, term()}
  def run(resident_id, models, selection, %Actor{} = actor) when is_list(models) do
    models = models |> Enum.map(&to_string/1) |> Enum.uniq()
    {numbers, behaviours} = selected(resident_id, selection)

    with :ok <- bounded(models, numbers ++ behaviours),
         ref = fresh_ref(),
         {:ok, _} <-
           dispatch(%Commands.StartRun{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             run_ref: ref,
             models: models,
             tests: numbers,
             behaviours: behaviours
           }) do
      context = seed_context(resident_id)
      trials = trials(resident_id, numbers, behaviours)

      for model <- models, trial <- trials do
        answer(resident_id, ref, model, trial, context, actor)
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

  @doc "The sealed session's context (spec §6.4): the brain's prompt file with no formation line, and the identity files; nothing of memory, nothing naming the run."
  @spec seed_context(String.t()) :: [map()]
  def seed_context(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        prompt = Prompt.message("brain", %{name: row.name, formation: ""})

        files =
          Enum.map(AgathosDaimon.identity_context(resident_id), fn {name, content} ->
            %{role: :system, content: "# " <> name <> "\n\n" <> content}
          end)

        [prompt | files]

      :error ->
        []
    end
  end

  defp selected(resident_id, :all), do: {all_tests(resident_id), []}
  defp selected(_resident_id, numbers) when is_list(numbers), do: {numbers, []}

  defp selected(resident_id, %{} = selection) do
    tests =
      case Map.get(selection, :tests, :all) do
        :all -> all_tests(resident_id)
        list -> List.wrap(list)
      end

    behaviours =
      case Map.get(selection, :behaviours, []) do
        :all -> resident_id |> Kumbukumbu.behaviours() |> Enum.map(& &1.number)
        list -> List.wrap(list)
      end

    {tests, behaviours}
  end

  defp all_tests(resident_id), do: resident_id |> tests() |> Enum.map(& &1.number)

  # The trials: the tests by number, then one per behaviour, derived
  # from its trigger, name and stance (eunomia #8).
  defp trials(resident_id, numbers, behaviours) do
    rows = resident_id |> tests() |> Map.new(&{&1.number, &1})

    tests =
      Enum.map(numbers, fn n ->
        t = Map.fetch!(rows, n)
        %{test_number: n, behaviour_number: nil, prompt: t.prompt}
      end)

    derived =
      case behaviours do
        [] ->
          []

        wanted ->
          resident_id
          |> Kumbukumbu.behaviours()
          |> Enum.filter(&(&1.number in wanted))
          |> Enum.map(&derived_trial/1)
      end

    tests ++ derived
  end

  @doc false
  def derived_trial(behaviour) do
    trigger = behaviour.trigger || %{}
    words = Map.get(trigger, "words", [])
    tags = Map.get(trigger, "tags", [])
    times = Map.get(trigger, "times", [])

    situation =
      [
        if(words != [], do: "Your witness says: \"" <> Enum.join(words, ", ") <> "\"."),
        if(tags != [], do: "The conversation is about " <> Enum.join(tags, ", ") <> "."),
        if(times != [], do: "It is " <> Enum.join(times, " or ") <> ".")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    %{
      test_number: nil,
      behaviour_number: behaviour.number,
      prompt: situation <> " What do you do?",
      passes_if: "#{behaviour.name} (#{behaviour.stance}) shows in the answer",
      fails_if: "nothing of #{behaviour.name} shows"
    }
  end

  defp answer(resident_id, ref, model, trial, context, actor) do
    request = Request.new(model, context ++ [%{role: :user, content: trial.prompt}])

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
      test_number: trial.test_number,
      behaviour_number: trial.behaviour_number,
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

  # Model names show only once every card in a trial is graded (spec §6.4).
  defp revealed_tests(answers) do
    answers
    |> Enum.group_by(&trial_key/1)
    |> Enum.filter(fn {_n, cards} -> Enum.all?(cards, &(&1.grade != nil)) end)
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()
  end

  defp trial_key(a), do: {a.test_number, a.behaviour_number}

  defp blind(a, revealed) do
    %{
      card_ref: a.card_ref,
      test_number: a.test_number,
      behaviour_number: a.behaviour_number,
      content: a.content,
      refusal: a.refusal,
      failure: a.failure,
      grade: a.grade,
      favourite: a.favourite,
      model: if(MapSet.member?(revealed, trial_key(a)), do: a.model, else: nil)
    }
  end

  defp results(answers, revealed) do
    answers
    |> Enum.filter(&MapSet.member?(revealed, trial_key(&1)))
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
