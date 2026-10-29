defmodule Oneiroi.Eunomia do
  @moduledoc """
  Judgement (spec §6.4): in this phase, regression per resident, sealed
  (F42). Tests are three texts; a run is models x tests, every candidate
  answering every test in a sealed session; each answer is a blind card
  the steward grades pass or fail, with favourites; model names show only
  once every card in a test is graded; the favourite can be pinned as the
  chat model through the resident system.

  The unawareness invariant (conventions §11): the suite lives on its own
  stream, none of its events are exported, no tool reads its rows, its
  calls are the `regression` purpose the resident's ledger view omits,
  and one test seeds a run with text unique to it and asserts every
  resident-reachable surface returns nothing of it.

  Positions, disputes, predictions, the nightly pass and the weekly audit
  are the next phase's.
  """
  use Oneiroi.System, slug: :eunomia

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.Brain,
      Oneiroi.Nisaba,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason
    ],
    exports: [
      Error,
      Regression,
      Router,
      Suite,
      Commands.WriteTest,
      Commands.ChangeTest,
      Commands.StartRun,
      Commands.RecordAnswer,
      Commands.FinishRun,
      Commands.GradeAnswer,
      Commands.FavouriteAnswer,
      Events.TestWritten,
      Events.TestChanged,
      Events.RunStarted,
      Events.AnswerRecorded,
      Events.RunFinished,
      Events.AnswerGraded,
      Events.AnswerFavourited,
      Store,
      Store.Test,
      Store.Run,
      Store.Answer
    ]

  alias Oneiroi.Eunomia.Regression

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:run_models_max, "EUNOMIA_RUN_MODELS_MAX",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage:
         "how many candidate models one regression run may hold; a bound on the steward's spend and the grader's deck"},
      {:run_tests_max, "EUNOMIA_RUN_TESTS_MAX",
       cast: :integer,
       default: "32",
       tag: :bound,
       usage:
         "how many tests one regression run may hold; a bound on the steward's spend and the grader's deck"}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Eunomia.Events.TestWritten, 1},
      {Oneiroi.Eunomia.Events.TestChanged, 1},
      {Oneiroi.Eunomia.Events.RunStarted, 1},
      {Oneiroi.Eunomia.Events.AnswerRecorded, 1},
      {Oneiroi.Eunomia.Events.RunFinished, 1},
      {Oneiroi.Eunomia.Events.AnswerGraded, 1},
      {Oneiroi.Eunomia.Events.AnswerFavourited, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:eunomia_test_invalid,
       "a test is three texts: the prompt, what passes, what fails, each at most 4,000 characters",
       remedy: "give all three"},
      {:eunomia_no_such_test, "no test has that number", remedy: "read the tests"},
      {:eunomia_run_empty, "a run needs at least one model and one test",
       remedy: "write a test, name a model"},
      {:eunomia_run_too_large,
       "a run is bounded in models and tests (EUNOMIA_RUN_MODELS_MAX, EUNOMIA_RUN_TESTS_MAX)",
       remedy: "run fewer at once"},
      {:eunomia_no_such_run, "no run has that ref", remedy: "read the runs"},
      {:eunomia_no_such_card, "no card in that run has that ref", remedy: "read the run"},
      {:eunomia_grade_invalid, "a grade is pass or fail", remedy: "swipe one way or the other"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Eunomia.Projectors.Regression]

  @doc "Writes a test (prompt, passes_if, fails_if); returns its number."
  @spec write_test(String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(write_test(resident_id, attrs, actor),
    do: Regression.write_test(resident_id, attrs, actor)
  )

  @doc "Changes a test's three texts."
  @spec change_test(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(change_test(resident_id, number, attrs, actor),
    do: Regression.change_test(resident_id, number, attrs, actor)
  )

  @doc "Runs the models against the tests (all, or the numbers given), synchronously; returns the run's ref."
  @spec run(String.t(), [String.t()], [pos_integer()] | :all, Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(run(resident_id, models, tests, actor),
    do: Regression.run(resident_id, models, tests, actor)
  )

  @doc "Grades a card pass or fail."
  @spec grade(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(grade(resident_id, run_ref, card_ref, grade, actor),
    do: Regression.grade(resident_id, run_ref, card_ref, grade, actor)
  )

  @doc "Favourites a card."
  @spec favourite(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(favourite(resident_id, run_ref, card_ref, actor),
    do: Regression.favourite(resident_id, run_ref, card_ref, actor)
  )

  @doc "The tests by number."
  @spec tests(String.t()) :: [Oneiroi.Eunomia.Store.Test.t()]
  defexport(tests(resident_id), do: Regression.tests(resident_id))

  @doc "The runs, newest first."
  @spec runs(String.t()) :: [Oneiroi.Eunomia.Store.Run.t()]
  defexport(runs(resident_id), do: Regression.runs(resident_id))

  @doc "A run with its cards blind and its results over the revealed tests."
  @spec run_detail(String.t(), String.t()) ::
          {:ok, Oneiroi.Eunomia.Store.Run.t(), [map()], [map()]} | {:error, term()}
  defexport(run_detail(resident_id, run_ref), do: Regression.run_detail(resident_id, run_ref))
end
