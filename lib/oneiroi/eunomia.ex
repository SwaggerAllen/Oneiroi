defmodule Oneiroi.Eunomia do
  @moduledoc """
  Judgement (spec §6.4): in this phase, regression per resident, sealed
  (F42). Tests are three texts; a run is models x tests, every candidate
  answering every test in a sealed session; each answer is a blind card
  the witness grades pass or fail, with favourites; model names show only
  once every card in a test is graded; the favourite can be pinned as the
  chat model through the resident system.

  The unawareness invariant (conventions §11): the suite lives on its own
  stream, none of its events are exported, no tool reads its rows, its
  calls are the `regression` purpose the resident's ledger view omits,
  and one test seeds a run with text unique to it and asserts every
  resident-reachable surface returns nothing of it.

  Judgement proper (P2): positions and their chains, disputes live and
  nightly with the judge's advice and model on every verdict, predictions
  the witness alone resolves, the nightly pass over the day's messages
  within David's bounds, and the judge chosen by the witness and never
  the resident's own chat model (F16, F17, F41). The weekly audit is the
  Honcho bridge's.
  """
  use Oneiroi.System, slug: :eunomia

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Ethos,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Oneiroi.Proteus,
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
      Jason,
      Oban
    ],
    exports: [
      Error,
      Regression,
      Router,
      Suite,
      Judgement,
      Judgements,
      Judge,
      JudgementRouter,
      NightWorker,
      MemoryAudit,
      AuditWorker,
      JudgementCommands.RunAudit,
      JudgementCommands.FailAudit,
      JudgementCommands.RaiseAuditFlag,
      JudgementCommands.ApproveAuditFlag,
      JudgementCommands.DeleteAuditFlag,
      JudgementCommands.RunWash,
      JudgementCommands.FailWash,
      JudgementCommands.RaiseWashFlag,
      JudgementCommands.ResolveWashFlag,
      Wash,
      Events.Judgement.AuditRun,
      Events.Judgement.AuditFailed,
      Events.Judgement.AuditFlagRaised,
      Events.Judgement.AuditFlagApproved,
      Events.Judgement.AuditFlagDeleted,
      Events.Judgement.WashRun,
      Events.Judgement.WashFailed,
      Events.Judgement.WashFlagRaised,
      Events.Judgement.WashFlagResolved,
      Store.Audit,
      Store.AuditFlag,
      JudgementCommands.TakePosition,
      JudgementCommands.ReplacePosition,
      JudgementCommands.CheckDispute,
      JudgementCommands.SettleDispute,
      JudgementCommands.RecordNight,
      JudgementCommands.FailNight,
      JudgementCommands.LogPrediction,
      JudgementCommands.ResolvePrediction,
      JudgementCommands.SetJudgeModel,
      Events.Judgement.PositionTaken,
      Events.Judgement.PositionReplaced,
      Events.Judgement.DisputeChecked,
      Events.Judgement.DisputeSettled,
      Events.Judgement.NightJudged,
      Events.Judgement.NightFailed,
      Events.Judgement.PredictionLogged,
      Events.Judgement.PredictionResolved,
      Events.Judgement.JudgeModelChanged,
      Store.Position,
      Store.Dispute,
      Store.Prediction,
      Store.Night,
      Store.JudgeChange,
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

  alias Oneiroi.Eunomia.Judgements
  alias Oneiroi.Eunomia.MemoryAudit
  alias Oneiroi.Eunomia.Regression
  alias Oneiroi.Eunomia.Wash

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
         "how many candidate models one regression run may hold; a bound on the witness's spend and the grader's deck"},
      {:run_tests_max, "EUNOMIA_RUN_TESTS_MAX",
       cast: :integer,
       default: "32",
       tag: :bound,
       usage:
         "how many tests one regression run may hold; a bound on the witness's spend and the grader's deck"},
      {:judge_model, "EUNOMIA_JUDGE_MODEL",
       default: "anthropic/claude-sonnet-4.5",
       usage:
         "the platform's judge model (F41), used unless the witness chooses another; a dated slug is what comparability wants and this default is a placeholder the author pins, not measured"},
      {:live_check_ms, "EUNOMIA_LIVE_CHECK_MS",
       cast: :integer,
       default: "90000",
       tag: :bound,
       usage:
         "how long a live dispute check waits for the judge before the resident is told to answer alone (spec §6.4's 90 seconds, carried from David)"},
      {:night_days, "EUNOMIA_NIGHT_DAYS",
       cast: :integer,
       default: "7",
       tag: :bound,
       usage: "how far back the nightly pass may read, in days (spec §6.4, carried from David)"},
      {:night_chars, "EUNOMIA_NIGHT_CHARS",
       cast: :integer,
       default: "200000",
       tag: :bound,
       usage:
         "how many characters of a day the nightly pass reads (spec §6.4, carried from David)"},
      {:message_chars, "EUNOMIA_MESSAGE_CHARS",
       cast: :integer,
       default: "4000",
       tag: :bound,
       usage:
         "how many characters of one message the nightly pass reads (spec §6.4, carried from David)"},
      {:audit_conclusions, "EUNOMIA_AUDIT_CONCLUSIONS",
       cast: :integer,
       default: "150",
       tag: :bound,
       usage:
         "how many of Honcho's conclusions the weekly memory audit reads (spec §6.4, carried from David)"},
      {:wash_entries, "EUNOMIA_WASH_ENTRIES",
       cast: :integer,
       default: "150",
       tag: :bound,
       usage:
         "how many entries of the identity files the weekly wash pass reads (spec §6.13, P18: judge-bounded at 150, the proposal's figure)"}
    ]
  end

  @impl Oneiroi.Component
  def oban_queues do
    [
      {:eunomia_nightly, cron: [{"0 2 * * *", Oneiroi.Eunomia.NightWorker}]},
      # After the card audit (03:00 Sunday, proteus): weekly, card then memory (spec §6.7).
      {:eunomia_weekly,
       cron: [
         {"0 4 * * 0", Oneiroi.Eunomia.AuditWorker},
         # The wash pass an hour after the memory audit (spec §6.13, P18).
         {"0 5 * * 0", Oneiroi.Eunomia.WashWorker}
       ]}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Eunomia.Events.TestWritten, 1},
      {Oneiroi.Eunomia.Events.TestChanged, 1},
      {Oneiroi.Eunomia.Events.RunStarted, 2},
      {Oneiroi.Eunomia.Events.AnswerRecorded, 2},
      {Oneiroi.Eunomia.Events.RunFinished, 1},
      {Oneiroi.Eunomia.Events.AnswerGraded, 1},
      {Oneiroi.Eunomia.Events.AnswerFavourited, 1},
      {Oneiroi.Eunomia.Events.Judgement.PositionTaken, 1},
      {Oneiroi.Eunomia.Events.Judgement.PositionReplaced, 1},
      {Oneiroi.Eunomia.Events.Judgement.DisputeChecked, 2},
      {Oneiroi.Eunomia.Events.Judgement.DisputeSettled, 1},
      {Oneiroi.Eunomia.Events.Judgement.NightJudged, 2},
      {Oneiroi.Eunomia.Events.Judgement.NightFailed, 1},
      {Oneiroi.Eunomia.Events.Judgement.PredictionLogged, 1},
      {Oneiroi.Eunomia.Events.Judgement.PredictionResolved, 1},
      {Oneiroi.Eunomia.Events.Judgement.JudgeModelChanged, 1},
      {Oneiroi.Eunomia.Events.Judgement.AuditRun, 2},
      {Oneiroi.Eunomia.Events.Judgement.AuditFailed, 1},
      {Oneiroi.Eunomia.Events.Judgement.AuditFlagRaised, 1},
      {Oneiroi.Eunomia.Events.Judgement.AuditFlagApproved, 1},
      {Oneiroi.Eunomia.Events.Judgement.AuditFlagDeleted, 1},
      {Oneiroi.Eunomia.Events.Judgement.WashRun, 1},
      {Oneiroi.Eunomia.Events.Judgement.WashFailed, 1},
      {Oneiroi.Eunomia.Events.Judgement.WashFlagRaised, 1},
      {Oneiroi.Eunomia.Events.Judgement.WashFlagResolved, 1}
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
      {:eunomia_grade_invalid, "a grade is pass or fail", remedy: "swipe one way or the other"},
      {:eunomia_not_the_resident,
       "positions, live checks, settlements and predictions are the resident's to make",
       remedy: "the resident does this from its own turn"},
      {:eunomia_not_the_witness,
       "resolving a prediction and choosing the judge are the witness's",
       remedy: "the witness does this from the client"},
      {:eunomia_statement_invalid,
       "a position or a prediction is one statement of at most 1,000 characters",
       remedy: "say it in fewer words"},
      {:eunomia_no_such_position, "no position has that number", remedy: "read the positions"},
      {:eunomia_position_replaced, "that position was already replaced; a chain cannot fork",
       remedy: "replace the head of the chain"},
      {:eunomia_dispute_invalid, "a check names its source and outcome from the closed sets",
       remedy: "this is the core's to build; report it"},
      {:eunomia_no_such_dispute, "no dispute has that ref", remedy: "read the disputes"},
      {:eunomia_settlement_invalid, "a dispute settles as conceded or held", remedy: "say which"},
      {:eunomia_no_such_prediction, "no prediction has that number",
       remedy: "read the predictions"},
      {:eunomia_resolution_invalid, "a prediction resolves as right, wrong or void",
       remedy: "say which"},
      {:eunomia_due_invalid, "a prediction is due at an instant", remedy: "give the instant"},
      {:eunomia_judge_model_invalid, "the judge is a model slug", remedy: "name the model"},
      {:eunomia_judge_is_the_chat_model,
       "the judge may never be the resident's own chat model (F41)",
       remedy: "choose another, or leave the platform's"},
      {:eunomia_night_out_of_reach,
       "the nightly pass reads a past day within its reach (EUNOMIA_NIGHT_DAYS)",
       remedy: "give a day from yesterday back to the bound"},
      {:eunomia_night_failed,
       "the judge's reply named a message it was not shown, so the night failed rather than be guessed at",
       remedy: "run the night again"},
      {:eunomia_audit_failed,
       "the judge's reply flagged a conclusion it was not shown, so the audit failed rather than be guessed at",
       remedy: "run the audit again"},
      {:eunomia_no_such_flag, "no audit flag has that ref", remedy: "read the audits"},
      {:eunomia_no_such_wash_flag, "no wash flag has that ref", remedy: "read the wash"},
      {:eunomia_wash_decision_invalid, "a wash flag is kept or edited",
       remedy: "decide keep, or edit and then make the edit yourself"},
      {:eunomia_wash_failed, "the wash pass failed and was recorded as such",
       remedy: "read the run's reason; the next week runs again"},
      {:eunomia_flag_decided, "that flag was already approved or deleted",
       remedy: "read the audits"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Eunomia.Projectors.Regression, Oneiroi.Eunomia.Projectors.Judgement]

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

  @doc "The sealed session's context (spec §6.4): the brain's prompt file and the identity files, nothing of memory."
  @spec seed_context(String.t()) :: [map()]
  defexport(seed_context(resident_id), do: Regression.seed_context(resident_id))

  # ---- judgement (spec §6.4) ----

  @doc "Takes a position in the resident's words; returns its number."
  @spec take_position(String.t(), String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(take_position(resident_id, statement, ctx, actor),
    do: Judgements.take_position(resident_id, statement, ctx, actor)
  )

  @doc "Replaces the head of a chain with a new position; returns the new number."
  @spec replace_position(String.t(), pos_integer(), String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(replace_position(resident_id, replaces, statement, ctx, actor),
    do: Judgements.replace_position(resident_id, replaces, statement, ctx, actor)
  )

  @doc "Every position with its place in its chain."
  @spec positions(String.t()) :: [Oneiroi.Eunomia.Store.Position.t()]
  defexport(positions(resident_id), do: Judgements.positions(resident_id))

  @doc "The positions still held: the head of every chain."
  @spec held_positions(String.t()) :: [Oneiroi.Eunomia.Store.Position.t()]
  defexport(held_positions(resident_id), do: Judgements.held_positions(resident_id))

  @doc "A live dispute check: the judge's advice within the bound, or timed out; recorded either way."
  @spec check_dispute(String.t(), map(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(check_dispute(resident_id, attrs, actor),
    do: Judgements.check_dispute(resident_id, attrs, actor)
  )

  @doc "The resident settles a dispute: conceded or held, with a note."
  @spec settle_dispute(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(settle_dispute(resident_id, ref, outcome, note, actor),
    do: Judgements.settle_dispute(resident_id, ref, outcome, note, actor)
  )

  @doc "The disputes, newest first."
  @spec disputes(String.t()) :: [Oneiroi.Eunomia.Store.Dispute.t()]
  defexport(disputes(resident_id), do: Judgements.disputes(resident_id))

  @doc "The Judgement screen's read: the judge, its changes, and the concession ratio by week."
  @spec judgement(String.t()) :: map()
  defexport(judgement(resident_id), do: Judgements.judgement(resident_id))

  @doc "The judge's model for the resident, never its own chat model."
  @spec judge_model(String.t()) :: String.t()
  defexport(judge_model(resident_id), do: Judgements.judge_model(resident_id))

  @doc "The witness chooses the judge; the resident's chat model is refused."
  @spec set_judge_model(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(set_judge_model(resident_id, model, actor),
    do: Judgements.set_judge_model(resident_id, model, actor)
  )

  @doc "Logs a prediction with its due instant; returns its number."
  @spec log_prediction(String.t(), String.t(), DateTime.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(log_prediction(resident_id, statement, due, ctx, actor),
    do: Judgements.log_prediction(resident_id, statement, due, ctx, actor)
  )

  @doc "Resolves a prediction right, wrong or void, with a note: the witness's alone."
  @spec resolve_prediction(String.t(), pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(resolve_prediction(resident_id, number, outcome, note, actor),
    do: Judgements.resolve_prediction(resident_id, number, outcome, note, actor)
  )

  @doc "Open soonest first, resolved with tallies."
  @spec predictions(String.t()) :: map()
  defexport(predictions(resident_id), do: Judgements.predictions(resident_id))

  @doc "Judges one day, once; what the nightly job does for each resident."
  @spec judge_night(String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | :already | {:error, term()}
  defexport(judge_night(resident_id, day, actor),
    do: Judgements.judge_night(resident_id, day, actor)
  )

  @doc "The nights, newest first."
  @spec nights(String.t()) :: [Oneiroi.Eunomia.Store.Night.t()]
  defexport(nights(resident_id), do: Judgements.nights(resident_id))

  @doc "Runs the weekly memory audit now: the judge over Honcho's conclusions; what the weekly job does for each resident."
  @spec run_audit(String.t(), Oneiroi.Actor.t()) :: {:ok, String.t()} | {:error, term()}
  defexport(run_audit(resident_id, actor), do: MemoryAudit.run(resident_id, actor))

  @doc "The witness approves a flag: the conclusion is deleted from Honcho; with a note."
  @spec approve_flag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(approve_flag(resident_id, ref, note, actor),
    do: MemoryAudit.approve(resident_id, ref, note, actor)
  )

  @doc "The witness deletes a flag: the conclusion stays; with a note."
  @spec delete_flag(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(delete_flag(resident_id, ref, note, actor),
    do: MemoryAudit.delete(resident_id, ref, note, actor)
  )

  @doc "The audit runs and the flags, open first."
  @spec audits(String.t()) :: map()
  defexport(audits(resident_id), do: MemoryAudit.audits(resident_id))

  # ---- the wash pass (spec §6.13, P18) ----

  @doc "Runs the weekly wash pass now: the judge over the identity files' entries; what the weekly job does for each resident."
  @spec run_wash(String.t(), Oneiroi.Actor.t()) :: {:ok, String.t()} | {:error, term()}
  defexport(run_wash(resident_id, actor), do: Wash.run(resident_id, actor))

  @doc "The resident decides a wash flag, keep or edit, with a note; the edit itself is the resident's soul edit."
  @spec resolve_wash_flag(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(resolve_wash_flag(resident_id, ref, decision, note, actor),
    do: Wash.resolve(resident_id, ref, decision, note, actor)
  )

  @doc "The wash runs and the flags, open first."
  @spec washes(String.t()) :: map()
  defexport(washes(resident_id), do: Wash.washes(resident_id))
end
