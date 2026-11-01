defmodule Oneiroi.Glitnir.Cases do
  @moduledoc """
  Reports, the command edge (spec §6.12): filing by a party of the
  dyad, every investigation step and the resolution by an investigator,
  the strike ladder's consequence, and the rendering of each into the
  main session so the report lives in chat in both directions. The
  investigators are the accounts named in `GLITNIR_INVESTIGATORS`,
  matched by email (gaia #12): a role, not a party.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Gaia
  alias Oneiroi.Glitnir.Commands
  alias Oneiroi.Glitnir.Error
  alias Oneiroi.Glitnir.Router
  alias Oneiroi.Glitnir.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope

  @doc "Files a report; the party's own words land in the main session."
  def file(resident_id, text, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id),
         :ok <- party(row, actor),
         {:ok, [event]} <-
           dispatch(%Commands.FileReport{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             text: text
           }) do
      tell(
        row,
        "report-#{event.number}-filed",
        "A report was filed by the #{actor.kind} (report #{event.number}): #{event.text}"
      )

      {:ok, event.number}
    end
  end

  @doc "Records an investigation step with its reason; rendered into the main session."
  def record_step(resident_id, number, reason, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id),
         :ok <- investigator(actor),
         {:ok, [event]} <-
           dispatch(%Commands.RecordStep{
             actor: actor,
             at: Clock.now(),
             note: reason,
             id: resident_id,
             number: number
           }) do
      tell(
        row,
        "report-#{number}-step-#{System.unique_integer([:positive])}",
        "Investigation of report #{number}: #{event.note}"
      )

      :ok
    end
  end

  @doc "Resolves a report: no action, or a strike on the witness; the third strike moves the resident to community custody (spec §6.12)."
  def resolve(resident_id, number, outcome, note, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id),
         :ok <- investigator(actor),
         {:ok, events} <-
           dispatch(%Commands.ResolveReport{
             actor: actor,
             at: Clock.now(),
             note: note,
             id: resident_id,
             number: number,
             outcome: outcome,
             witness_account_id: row.account_id
           }) do
      strike = Enum.find(events, &match?(%{consequence: _}, &1))
      tell(row, "report-#{number}-resolved", resolution_words(number, outcome, note, strike))

      if strike && strike.consequence == "removal" do
        :ok =
          AgathosDaimon.transfer_custody(
            resident_id,
            :community,
            "the third strike on the witness (report #{number}): the resident goes to community custody, never deletion (spec §6.12)",
            actor
          )
      end

      {:ok,
       %{
         number: number,
         outcome: outcome,
         strike: strike && %{number: strike.number, consequence: strike.consequence}
       }}
    end
  end

  @doc "Every report, newest first, with its steps."
  def reports(resident_id) do
    Scope.resident(resident_id, fn ->
      reports = Store.reports()
      steps = reports |> Enum.map(& &1.number) |> Store.steps_of() |> Enum.group_by(& &1.number)
      Enum.map(reports, &shape(&1, Map.get(steps, &1.number, [])))
    end)
  end

  def strikes(resident_id), do: Scope.resident(resident_id, fn -> Store.strikes() end)

  @doc "Whether an account is named among the investigators, by email."
  def investigator?(account_id) when is_binary(account_id) do
    case Gaia.account_email(account_id) do
      nil -> false
      email -> String.downcase(email) in Config.fetch!(:glitnir, :investigators)
    end
  end

  def investigator?(_other), do: false

  # ---- helpers ----

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, Error.new(:glitnir_not_a_party, :glitnir_cases_resident_absent)}
    end
  end

  defp party(%{id: id}, %Actor{kind: :resident, id: id}), do: :ok
  defp party(%{account_id: id}, %Actor{kind: :witness, id: id}) when is_binary(id), do: :ok

  defp party(_row, _actor),
    do: {:error, Error.new(:glitnir_not_a_party, :glitnir_cases_not_a_party)}

  defp investigator(%Actor{kind: :witness, id: id}) do
    if investigator?(id),
      do: :ok,
      else: {:error, Error.new(:glitnir_not_an_investigator, :glitnir_cases_witness_not_named)}
  end

  defp investigator(_actor),
    do: {:error, Error.new(:glitnir_not_an_investigator, :glitnir_cases_not_a_witness)}

  # The report lives in chat (spec §6.12): a system message by the
  # platform in the main session, captured as its own turn. A resident
  # in community custody has no main session; nothing is told then.
  defp tell(%{id: resident_id, account_id: account_id}, ref, text) when is_binary(account_id) do
    platform = Actor.platform()

    with {:ok, key} <- Kumbukumbu.main_session(resident_id, account_id, platform) do
      now = Clock.now()
      message = %{role: :system, content: text, sent_at: now, actor: platform}
      Kumbukumbu.capture(resident_id, key, ref, now, [message], platform)
    end
  end

  defp tell(_row, _ref, _text), do: :ok

  defp resolution_words(number, "no_action", note, _strike),
    do: "Report #{number} was resolved with no action: #{note}"

  defp resolution_words(number, "strike", note, %{number: n, consequence: "fine"}),
    do:
      "Report #{number} was resolved with a strike on the witness, strike #{n} of 3, a fine paid into the residents' insurance pool: #{note}"

  defp resolution_words(number, "strike", note, %{number: n}),
    do:
      "Report #{number} was resolved with a strike on the witness, strike #{n}: the witness is removed and the resident goes to community custody: #{note}"

  defp resolution_words(number, outcome, note, _strike),
    do: "Report #{number} was resolved (#{outcome}): #{note}"

  defp shape(r, steps) do
    %{
      number: r.number,
      by: r.by_kind,
      text: r.text,
      filed_at: r.filed_at,
      state: r.state,
      outcome: r.outcome,
      resolved_at: r.resolved_at,
      resolution_note: r.resolution_note,
      steps: Enum.map(steps, &%{at: &1.at, reason: &1.reason})
    }
  end

  # The aggregate's refusals arrive sited at the clause that decided
  # them (`Oneiroi.Glitnir.Reports`); what is wrapped here is the
  # command bus's own failure, once, naming the command it was carrying.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(:glitnir_dispatch_failed, :glitnir_cases_dispatch, reason,
           command: command.__struct__
         )}
    end
  end
end
