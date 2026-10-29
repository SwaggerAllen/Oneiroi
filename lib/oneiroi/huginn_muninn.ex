defmodule Oneiroi.HuginnMuninn do
  @moduledoc """
  Audits (spec §6.13): figures (counters as the fold of their increments
  and countdowns derived from dates, F57), the steward's own audits over
  them (F48), the built-in checklist, and the check-engine light as the
  failing results of the audits that count (F49). Audits read rows and
  never transcript text; results are private to the dyad; never a
  leaderboard.
  """
  use Oneiroi.System, slug: :huginn_muninn

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Eunomia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Proteus,
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
      Store.Run
    ]

  alias Oneiroi.HuginnMuninn.Checks
  alias Oneiroi.HuginnMuninn.Figures

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:missed_checkins_warn, "HUGINN_MUNINN_MISSED_CHECKINS_WARN",
       cast: :integer,
       default: "3",
       tag: :bound,
       usage:
         "how many missed check-ins in a week the built-in audit warns at; a guess at what a steward would want told, not measured"}
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
      {:huginn_muninn_not_the_steward,
       "defining and retiring counters and audits are the steward's",
       remedy: "the steward does this from the client"},
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
      {:huginn_muninn_no_such_audit, "no audit of the steward's has that key",
       remedy: "read the audits"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.HuginnMuninn.Projectors.Audits]

  @doc "Defines a counter (the steward's): a key and a label."
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

  @doc "Retires a counter (the steward's)."
  @spec retire_counter(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(retire_counter(resident_id, key, actor),
    do: Figures.retire_counter(resident_id, key, actor)
  )

  @doc "Every figure, fresh: counters and countdowns."
  @spec figures(String.t()) :: [map()]
  defexport(figures(resident_id), do: Figures.figures(resident_id))

  @doc "One figure by key, or nil."
  @spec figure(String.t(), String.t()) :: map() | nil
  defexport(figure(resident_id, key), do: Figures.figure(resident_id, key))

  @doc "A counter's latest increments with their actors."
  @spec increments(String.t(), String.t(), pos_integer()) :: [
          Oneiroi.HuginnMuninn.Store.Increment.t()
        ]
  defexport(increments(resident_id, key, limit), do: Figures.increments(resident_id, key, limit))

  @doc "The figures section the brain reads; empty when there are no counters."
  @spec figures_text(String.t()) :: String.t()
  defexport(figures_text(resident_id), do: Figures.text(resident_id))

  @doc "Defines a steward's audit over a figure."
  @spec define_audit(String.t(), map(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(define_audit(resident_id, attrs, actor), do: Checks.define(resident_id, attrs, actor))

  @doc "Retires a steward's audit."
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
