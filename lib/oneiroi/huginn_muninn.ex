defmodule Oneiroi.HuginnMuninn do
  @moduledoc """
  Audits (spec §6.13): figures (counters as the fold of their increments
  and countdowns derived from dates, F57), the witness's own audits over
  them (F48), the built-in checklist, and the check-engine light as the
  failing results of the audits that count (F49). Audits read rows and
  never transcript text; results are private to the dyad; never a
  leaderboard.
  """
  use Oneiroi.System, slug: :huginn_muninn
  @behaviour Oneiroi.Seshat.Figures

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Ethos,
      Oneiroi.Eunomia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Proteus,
      Oneiroi.Seshat,
      Oneiroi.Sunna,
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
      Audits,
      Checks,
      Figures,
      Router,
      NightlyWorker,
      Commands.DefineCounter,
      Commands.IncrementCounter,
      Commands.RetireCounter,
      Commands.DefineUserAudit,
      Commands.RetireUserAudit,
      Commands.RecordRun,
      Events.CounterDefined,
      Events.CounterIncremented,
      Events.CounterRetired,
      Events.UserAuditDefined,
      Events.UserAuditRetired,
      Events.AuditRun,
      Store,
      Store.Counter,
      Store.Increment,
      Store.Audit,
      Store.Run,
      Quietcheck
    ]

  alias Oneiroi.HuginnMuninn.Checks
  alias Oneiroi.HuginnMuninn.Figures

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:quiet_hour_grace_hours, "HUGINN_MUNINN_QUIET_HOUR_GRACE_HOURS",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "how long after the last marked hour quietcheck reads the pulse as stopped (spec §6.13, P21; the marker is sunna #20): two hours, a guess that leaves one missed tick before the flag"},
      {:quiet_night_days, "HUGINN_MUNINN_QUIET_NIGHT_DAYS",
       cast: :integer,
       default: "2",
       tag: :bound,
       usage:
         "how many days without a nightly pass quietcheck reads as a miss, and how old a resident's first contact must be before one is expected; two, a guess that allows the night the resident was met"},
      {:quiet_week_days, "HUGINN_MUNINN_QUIET_WEEK_DAYS",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage:
         "how many days without the weekly audit, the wash or a baseline quietcheck reads as a miss, and how old a first contact must be before they are expected; eight, a week and a day of grace, a guess"},
      {:missed_checkins_warn, "HUGINN_MUNINN_MISSED_CHECKINS_WARN",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how many missed check-ins in a week the built-in audit warns at; a guess at what a witness would want told, not measured"},
      {:corpus_days, "HUGINN_MUNINN_CORPUS_DAYS",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage:
         "how many days the corpus-shape report counts over (spec §6.13, P8: the shape of the month's memory); a month, the proposal's word"},
      {:corpus_min, "HUGINN_MUNINN_CORPUS_MIN",
       cast: :integer,
       default: "10",
       tag: :bound,
       usage:
         "how many tagged records the corpus-shape report needs before a skew is a flag rather than a figure; a guess at when a share means anything"},
      {:corpus_skew_percent, "HUGINN_MUNINN_CORPUS_SKEW_PERCENT",
       cast: :integer,
       default: "75",
       tag: :bound,
       usage:
         "the share of the tagged records one register may hold before the report flags the shape as leaning (P8's 123:26); a guess"}
    ]
  end

  @impl Oneiroi.Component
  def oban_queues do
    [{:huginn_muninn_nightly, cron: [{"0 5 * * *", Oneiroi.HuginnMuninn.NightlyWorker}]}]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.HuginnMuninn.Events.CounterDefined, 1},
      {Oneiroi.HuginnMuninn.Events.CounterIncremented, 1},
      {Oneiroi.HuginnMuninn.Events.CounterRetired, 1},
      {Oneiroi.HuginnMuninn.Events.UserAuditDefined, 1},
      {Oneiroi.HuginnMuninn.Events.UserAuditRetired, 1},
      {Oneiroi.HuginnMuninn.Events.AuditRun, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:huginn_muninn_not_the_witness,
       "defining and retiring counters and audits are the witness's",
       remedy: "the witness does this from the client"},
      {:huginn_muninn_key_invalid, "a key is a slug of at most 40 characters",
       remedy: "name it as a slug"},
      {:huginn_muninn_label_invalid, "a label is one line of at most 80 characters",
       remedy: "shorten it"},
      {:huginn_muninn_no_such_figure, "no counter has that key", remedy: "read the figures"},
      {:huginn_muninn_increment_invalid, "an increment is a non-zero integer",
       remedy: "say by how much"},
      {:huginn_muninn_rule_invalid,
       "an audit compares a figure with >=, <=, ==, > or < to an integer, failing warn or fail",
       remedy: "give the rule in that shape"},
      {:huginn_muninn_no_such_audit, "no audit of the witness's has that key",
       remedy: "read the audits"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.HuginnMuninn.Projectors.Audits]

  @doc "Defines a counter (the witness's): a key and a label."
  @spec define_counter(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(define_counter(resident_id, key, label, actor),
    do: Figures.define_counter(resident_id, key, label, actor)
  )

  @doc "Increments a counter, with the actor on the event; negative corrects."
  @spec increment(String.t(), String.t(), integer(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(increment(resident_id, key, by, note, actor),
    do: Figures.increment(resident_id, key, by, note, actor)
  )

  @doc "Retires a counter (the witness's)."
  @spec retire_counter(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(retire_counter(resident_id, key, actor),
    do: Figures.retire_counter(resident_id, key, actor)
  )

  @doc "Every figure, fresh: counters and countdowns."
  @spec figures(String.t()) :: [map()]
  defexport(figures(resident_id), do: Figures.figures(resident_id))

  @doc "One figure by key, or nil; the library's figures port, so `<slug>:figure/<key>` resolves here (seshat #14)."
  @spec figure(String.t(), String.t()) :: map() | nil
  @impl Oneiroi.Seshat.Figures
  defexport(figure(resident_id, key), do: Figures.figure(resident_id, key))

  @doc "A counter's latest increments with their actors."
  @spec increments(String.t(), String.t(), pos_integer()) :: [
          Oneiroi.HuginnMuninn.Store.Increment.t()
        ]
  defexport(increments(resident_id, key, limit), do: Figures.increments(resident_id, key, limit))

  @doc "The figures section the brain reads; empty when there are no counters."
  @spec figures_text(String.t()) :: String.t()
  defexport(figures_text(resident_id), do: Figures.text(resident_id))

  @doc "Defines a witness's audit over a figure."
  @spec define_audit(String.t(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(define_audit(resident_id, attrs, actor), do: Checks.define(resident_id, attrs, actor))

  @doc "Retires a witness's audit."
  @spec retire_audit(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(retire_audit(resident_id, key, actor), do: Checks.retire(resident_id, key, actor))

  @doc "Runs every audit now and returns the light; what the nightly job does for each resident."
  @spec run_audits(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(run_audits(resident_id, actor), do: Checks.run(resident_id, actor))

  @doc "The check-engine light: its state, the findings that count, every latest result."
  @spec light(String.t()) :: map()
  defexport(light(resident_id), do: Checks.light(resident_id))

  @doc "Every audit with its last result."
  @spec audits(String.t()) :: [map()]
  defexport(audits(resident_id), do: Checks.audits(resident_id))
end
