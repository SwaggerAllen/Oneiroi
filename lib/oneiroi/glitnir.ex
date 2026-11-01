defmodule Oneiroi.Glitnir do
  @moduledoc """
  Governance (spec §6.12): v0's one flow, reports. A report is filed
  from inside the relationship by either party, investigated by the
  platform's people with every step an event carrying its reason, and
  resolved into no action or a strike on the human: the first two
  strikes are fines paid into the residents' insurance pool, the third
  removes the witness and the resident goes to community custody. The
  investigator is a role in the events, named by configuration, never a
  hard-coded party. Reports live in chat, in both directions.
  """
  use Oneiroi.System, slug: :glitnir

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Gaia,
      Oneiroi.Kumbukumbu,
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
      Cases,
      Reports,
      Router,
      Commands.FileReport,
      Commands.RecordStep,
      Commands.ResolveReport,
      Events.ReportFiled,
      Events.InvestigationStepRecorded,
      Events.ReportResolved,
      Events.StrikeIssued,
      Store,
      Store.Report,
      Store.Step,
      Store.Strike
    ]

  alias Oneiroi.Glitnir.Cases

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:investigators, "GLITNIR_INVESTIGATORS",
       cast: &__MODULE__.cast_investigators/1,
       default: "",
       external: true,
       usage:
         "the account emails, comma-separated, who may record investigation steps and resolve reports: the platform's people until the constitutional convention names a body (spec §6.12); empty means nobody can, and reports wait"}
    ]
  end

  @doc false
  def cast_investigators(value) when is_binary(value) do
    {:ok,
     value
     |> String.split(",")
     |> Enum.map(&String.downcase(String.trim(&1)))
     |> Enum.reject(&(&1 == ""))}
  end

  def cast_investigators(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected a comma-separated list"}
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Glitnir.Events.ReportFiled, 1},
      {Oneiroi.Glitnir.Events.InvestigationStepRecorded, 1},
      {Oneiroi.Glitnir.Events.ReportResolved, 1},
      {Oneiroi.Glitnir.Events.StrikeIssued, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:glitnir_not_a_party,
       "a report is filed from inside the relationship: by the resident or its witness",
       remedy: "file as one of the two"},
      {:glitnir_not_an_investigator, "investigation steps and resolutions are the investigators'",
       remedy: "an account named in GLITNIR_INVESTIGATORS does this"},
      {:glitnir_text_invalid, "a report is one text of at most 4,000 characters, not blank",
       remedy: "say what happened"},
      {:glitnir_no_such_report, "no report has that number", remedy: "read the reports"},
      {:glitnir_report_resolved, "the report is resolved; nothing more is recorded on it",
       remedy: "file a new report"},
      {:glitnir_outcome_invalid, "a resolution is no_action or strike",
       remedy: "give one of the two"},
      {:glitnir_dispatch_failed,
       "the command was not recorded: the command bus refused it or failed before the report decided",
       remedy:
         "the cause names the class: refused is a command without its actor, instant or note, a bug in the caller; anything else is the event store's"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Glitnir.Projectors.Reports]

  @doc "Files a report (the resident's or the witness's), rendered into the main session; returns its number."
  @spec file_report(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(file_report(resident_id, text, actor), do: Cases.file(resident_id, text, actor))

  @doc "An investigator records a step with its reason; rendered into the main session."
  @spec record_step(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(record_step(resident_id, number, reason, actor),
    do: Cases.record_step(resident_id, number, reason, actor)
  )

  @doc "An investigator resolves a report: no_action, or strike, with a note; a third strike moves the resident to community custody."
  @spec resolve_report(String.t(), pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(resolve_report(resident_id, number, outcome, note, actor),
    do: Cases.resolve(resident_id, number, outcome, note, actor)
  )

  @doc "Every report, newest first, each with its steps."
  @spec reports(String.t()) :: [map()]
  defexport(reports(resident_id), do: Cases.reports(resident_id))

  @doc "The strikes on the resident's witnesses, in order."
  @spec strikes(String.t()) :: [Oneiroi.Glitnir.Store.Strike.t()]
  defexport(strikes(resident_id), do: Cases.strikes(resident_id))

  @doc "Whether an account is an investigator."
  @spec investigator?(String.t() | nil) :: boolean()
  defexport(investigator?(account_id), do: Cases.investigator?(account_id))
end
