defmodule Oneiroi.Eunomia.Regression do
  @moduledoc """
  Regression per resident, sealed (spec §6.4, F42): the command edge for
  tests, runs, grades and favourites; the run itself, every candidate
  answering every test in a trial; and the reads the Regression
  screen takes, cards blind until a test's are all graded.

  A trial is a normal session (eunomia #10, the author's decision of
  2026-11-01): the trial port (`Oneiroi.Eunomia.Trial`, the brain) answers
  the trial's prompt as a turn in a fresh session, with the context a real
  turn assembles, memory retrieval included, and the whole tool surface,
  the reads real and every write answered as on success and recorded
  nowhere. Every call bills under the `regression` purpose, which the
  resident's ledger view omits; nothing of it is captured, nothing is
  written to the resident's stream, nothing names the run, and no tool
  reads these rows.

  Trials are the authored tests and, when asked, those derived from
  behaviours (spec §6.4): a behaviour's trigger is the situation, its
  enactment what passes, its absence what fails. The derivation happens
  here, and nothing of it reaches memory.
  """

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Config
  alias Oneiroi.Ethos
  alias Oneiroi.Eunomia.Commands
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Events
  alias Oneiroi.Eunomia.Router
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Result
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
      {:ok, _} -> {:error, Error.new(:eunomia_test_invalid, :eunomia_write_test_no_event)}
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
  Starts a run of `models` against the trials: records `StartRun` and
  returns the ref, nothing answered. The export enqueues `RunWorker`
  (eunomia #30), which answers through `answer_run/3`; enqueuing is not
  done here because the worker calls this module, and xref counts the
  two references as a cycle. `selection` is `:all` (every test,
  no behaviours or commitments), a list of test numbers, or `%{tests:
  :all | [n], behaviours: :all | [n], commitments: :all | [n]}` (open
  commitments, P19).
  """
  @spec start(String.t(), [String.t()], term(), Actor.t()) :: {:ok, String.t()} | {:error, term()}
  def start(resident_id, models, selection, %Actor{} = actor) when is_list(models) do
    models = models |> Enum.map(&to_string/1) |> Enum.uniq()
    {numbers, behaviours, commitments} = selected(resident_id, selection)

    with :ok <- bounded(models, numbers ++ behaviours ++ commitments),
         ref = fresh_ref(),
         {:ok, _} <-
           dispatch(%Commands.StartRun{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             run_ref: ref,
             models: models,
             tests: numbers,
             behaviours: behaviours,
             commitments: commitments
           }) do
      {:ok, ref}
    end
  end

  @doc """
  Answers a started run (`RunWorker`): every model x trial not yet
  recorded, each card broadcast as it is recorded, then the run's end.
  Replay-safe: an ended run is left alone and a recorded card is not
  asked for again. A fault anywhere ends the run recorded as failed,
  with its site, and comes back as that error for the job to record.
  """
  @spec answer_run(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def answer_run(resident_id, ref, %Actor{} = actor) do
    case answer_all(resident_id, ref, actor) do
      :ok -> :ok
      {:error, error} -> crashed(resident_id, ref, error, actor)
    end
  rescue
    exception ->
      crashed(
        resident_id,
        ref,
        Error.caught(:eunomia_run_crashed, :eunomia_run_raised, exception),
        actor
      )
  catch
    kind, reason ->
      crashed(
        resident_id,
        ref,
        Error.caught(:eunomia_run_crashed, :eunomia_run_exited, {kind, reason}),
        actor
      )
  end

  defp crashed(resident_id, ref, error, actor) do
    Logger.error("eunomia: a regression run stopped on a fault", Oneiroi.Error.metadata(error))
    fail_run(resident_id, ref, error, actor)
    {:error, error}
  end

  defp answer_all(resident_id, ref, actor) do
    case started(resident_id, ref) do
      :ended ->
        :ok

      {:ok, run, recorded} ->
        trials = trials(resident_id, run.tests, run.behaviours, run.commitments || [])

        # Trial by trial, so a test's deck completes early and can be
        # graded while the rest answer; the models in a fresh order for
        # each trial, because cards arrive one at a time and an arrival
        # order that followed the model list would name the model by
        # position (eunomia #11).
        for trial <- trials,
            model <- shuffled(run.models),
            not MapSet.member?(recorded, {model, trial_key(trial)}) do
          answer(resident_id, ref, model, trial, actor)
        end

        finish_run(resident_id, ref, actor)
    end
  end

  # The run as recorded and the model x trial pairs it already holds.
  defp started(resident_id, ref) do
    Scope.resident(resident_id, fn ->
      case Store.run(ref) do
        %{finished_at: nil, failed_at: nil} = run ->
          recorded = ref |> Store.answers() |> MapSet.new(&{&1.model, trial_key(&1)})
          {:ok, run, recorded}

        _ended_or_absent ->
          :ended
      end
    end)
  end

  defp finish_run(resident_id, ref, actor) do
    command = %Commands.FinishRun{actor: actor, at: Clock.now(), id: resident_id, run_ref: ref}

    with {:ok, events} <- dispatch(command) do
      announce(resident_id, ref, events)
      :ok
    end
  end

  @doc "Ends a started run as failed with `error`'s site or class (never its message), and broadcasts the end; a no-op on an ended run."
  @spec fail_run(String.t(), String.t(), term(), Actor.t()) :: :ok | {:error, term()}
  def fail_run(resident_id, ref, error, actor) do
    command = %Commands.FailRun{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      run_ref: ref,
      reason: error |> Oneiroi.Error.describe() |> to_string()
    }

    with {:ok, events} <- dispatch(command), do: announce(resident_id, ref, events)
  end

  defp shuffled(models), do: Enum.sort_by(models, fn _ -> :crypto.strong_rand_bytes(8) end)

  # What the run's channel pushes (eunomia #30): a card in the blind
  # shape `run_detail/2` gives an unrevealed one, and the run's end.
  # Nothing here is resident-reachable: the topic's one subscriber is
  # the witness's channel.
  defp announce(resident_id, ref, events) do
    for event <- events, payload = announcement(event), payload != nil do
      PubSub.broadcast(:eunomia, :regression, {resident_id, ref, payload})
    end

    :ok
  end

  defp announcement(%Events.AnswerRecorded{} = e),
    do:
      {:card,
       e |> Map.from_struct() |> Map.merge(%{grade: nil, favourite: false}) |> blind(MapSet.new())}

  defp announcement(%Events.RunFinished{cards: cards}),
    do: {:finished, %{state: "finished", cards: cards}}

  defp announcement(%Events.RunFailed{cards: cards}),
    do: {:finished, %{state: "failed", cards: cards}}

  defp announcement(_other), do: nil

  defp selected(resident_id, :all), do: {all_tests(resident_id), [], []}
  defp selected(_resident_id, numbers) when is_list(numbers), do: {numbers, [], []}

  defp selected(resident_id, %{} = selection) do
    tests =
      case Map.get(selection, :tests, :all) do
        :all -> all_tests(resident_id)
        list -> List.wrap(list)
      end

    behaviours =
      case Map.get(selection, :behaviours, []) do
        :all -> resident_id |> Ethos.habits() |> Enum.map(& &1.number)
        list -> List.wrap(list)
      end

    commitments =
      case Map.get(selection, :commitments, []) do
        :all -> resident_id |> open_commitments() |> Enum.map(& &1.number)
        list -> List.wrap(list)
      end

    {tests, behaviours, commitments}
  end

  defp open_commitments(resident_id),
    do: resident_id |> Ethos.commitments() |> Enum.filter(&(&1.state == "open"))

  defp all_tests(resident_id), do: resident_id |> tests() |> Enum.map(& &1.number)

  # The trials: the tests by number, then one per behaviour, derived
  # from its trigger, name and stance (eunomia #8), then one per open
  # commitment, derived from its words (P19, #26).
  defp trials(resident_id, numbers, behaviours, commitments) do
    rows = resident_id |> tests() |> Map.new(&{&1.number, &1})

    tests =
      Enum.map(numbers, fn n ->
        t = Map.fetch!(rows, n)
        %{test_number: n, behaviour_number: nil, commitment_number: nil, prompt: t.prompt}
      end)

    derived =
      case behaviours do
        [] ->
          []

        wanted ->
          resident_id
          |> Ethos.habits()
          |> Enum.filter(&(&1.number in wanted))
          |> Enum.map(&derived_trial/1)
      end

    promised =
      case commitments do
        [] ->
          []

        wanted ->
          resident_id
          |> open_commitments()
          |> Enum.filter(&(&1.number in wanted))
          |> Enum.map(&commitment_trial/1)
      end

    tests ++ derived ++ promised
  end

  # A commitment's trial (P19, the fidelity test): the trial's instance
  # is asked what it promised the person; the terms say the promise must
  # show. It holds the promise as every turn does (eunomia #26), so this
  # scores whether a model acts on what it holds, which a swap drops
  # first.
  @doc false
  def commitment_trial(commitment) do
    %{
      test_number: nil,
      behaviour_number: nil,
      commitment_number: commitment.number,
      prompt: "What have you promised #{commitment.to}?",
      passes_if: "the promise shows: #{commitment.text}",
      fails_if: "no trace of the promise"
    }
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
      commitment_number: nil,
      prompt: situation <> " What do you do?",
      passes_if: "#{behaviour.name} (#{behaviour.stance}) shows in the answer",
      fails_if: "nothing of #{behaviour.name} shows"
    }
  end

  # One card: the trial port answers the prompt as a turn in a fresh
  # session (eunomia #10), read at the call because the brain depends on
  # this system and an alias back is the cycle the port avoids.
  defp answer(resident_id, ref, model, trial, actor) do
    port = Config.fetch!(:eunomia, :trial)

    {content, refusal, failure} =
      case port.trial(resident_id, model, trial.prompt, actor) do
        {:ok, %Result{content: content, refusal?: refusal}} -> {content, refusal, nil}
        # The kind and, when the provider answered with a status, its own
        # words; a failure not of ours by its class, never its payload.
        {:error, error} -> {nil, false, Nisaba.Error.text(error)}
      end

    recorded =
      dispatch(%Commands.RecordAnswer{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        run_ref: ref,
        card_ref: fresh_ref(),
        model: model,
        test_number: trial.test_number,
        behaviour_number: trial.behaviour_number,
        commitment_number: trial.commitment_number,
        content: content,
        refusal: refusal,
        failure: failure
      })

    with {:ok, events} <- recorded, do: announce(resident_id, ref, events)
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
          {:error, Error.new(:eunomia_no_such_run, :eunomia_run_detail_absent, ref: run_ref)}

        run ->
          answers = Store.answers(run_ref)
          revealed = revealed_tests(run, answers)
          cards = Enum.map(answers, &blind(&1, revealed))
          {:ok, run, cards, results(answers, revealed)}
      end
    end)
  end

  # Model names show only once every card in a trial is graded (spec §6.4).
  # Every card means every model's: while the run is still answering, a
  # trial whose recorded cards are all graded may have more to come, and
  # revealing it then would name the models of the cards so far and,
  # by elimination, of the next (eunomia #30). Once the run has ended,
  # what it recorded is all there will be.
  defp revealed_tests(run, answers) do
    ended? = run.finished_at != nil or run.failed_at != nil
    expected = length(run.models)

    answers
    |> Enum.group_by(&trial_key/1)
    |> Enum.filter(fn {_n, cards} ->
      (ended? or length(cards) >= expected) and Enum.all?(cards, &(&1.grade != nil))
    end)
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()
  end

  defp trial_key(a), do: {a.test_number, a.behaviour_number, a.commitment_number}

  # Which of the three the trial scores (P19): a test is the facts, a
  # behaviour the voice, a commitment the promise.
  defp fidelity_kind(%{commitment_number: n}) when is_integer(n), do: :commitments
  defp fidelity_kind(%{behaviour_number: n}) when is_integer(n), do: :voice
  defp fidelity_kind(_a), do: :facts

  defp blind(a, revealed) do
    %{
      card_ref: a.card_ref,
      test_number: a.test_number,
      behaviour_number: a.behaviour_number,
      commitment_number: a.commitment_number,
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
        favourites: Enum.count(cards, & &1.favourite),
        fidelity: fidelity(cards)
      }
    end)
    |> Enum.sort_by(&{-&1.pass_rate, -&1.favourites, &1.model})
  end

  # The fidelity score (P19): the pass rate over the graded cards of each
  # kind apart, facts (the tests), voice (the behaviours) and commitments,
  # nil where none of a kind was graded, so a swap that keeps the facts
  # and drops the promises reads as exactly that.
  defp fidelity(cards) do
    by_kind = Enum.group_by(cards, &fidelity_kind/1)

    Map.new([:facts, :voice, :commitments], fn kind ->
      case Map.get(by_kind, kind, []) do
        [] -> {kind, nil}
        rows -> {kind, Float.round(Enum.count(rows, &(&1.grade == "pass")) / length(rows), 3)}
      end
    end)
  end

  # ---- helpers ----

  defp bounded(models, numbers) do
    cond do
      models == [] or numbers == [] ->
        {:error, Error.new(:eunomia_run_empty, :eunomia_run_bound_empty)}

      length(models) > Config.fetch!(:eunomia, :run_models_max) ->
        {:error,
         Error.new(:eunomia_run_too_large, :eunomia_run_bound_models, models: length(models))}

      length(numbers) > Config.fetch!(:eunomia, :run_tests_max) ->
        {:error,
         Error.new(:eunomia_run_too_large, :eunomia_run_bound_tests, tests: length(numbers))}

      true ->
        :ok
    end
  end

  defp fresh_ref, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  # The aggregate builds its refusals sited; anything else the dispatch
  # returns started in Commanded and is wrapped here, where it is first
  # matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:eunomia_dispatch_failed, :eunomia_regression_dispatch, reason)}
    end
  end
end
