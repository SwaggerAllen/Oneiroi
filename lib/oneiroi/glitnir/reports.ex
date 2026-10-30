defmodule Oneiroi.Glitnir.Reports do
  @moduledoc """
  The governance aggregate on `governance-<resident_id>` (spec §6.12).
  Pure: the reports by number with whether each is resolved, and the
  count of strikes, so the third is the aggregate's to name as a
  removal. Who may file or investigate is the service's to check,
  because it reads the resident's witness and the investigators list.
  """

  alias Oneiroi.Glitnir.Commands
  alias Oneiroi.Glitnir.Events

  defstruct [:id, reports: %{}, count: 0, strikes: 0]

  @outcomes ~w(no_action strike)
  @text_limit 4_000

  def execute(%__MODULE__{count: count}, %Commands.FileReport{} = c) do
    if text_ok?(c.text),
      do: %Events.ReportFiled{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: count + 1,
        text: String.trim(c.text)
      },
      else: {:error, :text_invalid}
  end

  def execute(%__MODULE__{reports: reports}, %Commands.RecordStep{} = c) do
    case Map.get(reports, c.number) do
      nil ->
        {:error, :no_such_report}

      :resolved ->
        {:error, :report_resolved}

      :open ->
        %Events.InvestigationStepRecorded{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          number: c.number
        }
    end
  end

  def execute(%__MODULE__{reports: reports, strikes: strikes}, %Commands.ResolveReport{} = c) do
    cond do
      c.outcome not in @outcomes ->
        {:error, :outcome_invalid}

      Map.get(reports, c.number) == nil ->
        {:error, :no_such_report}

      Map.get(reports, c.number) == :resolved ->
        {:error, :report_resolved}

      true ->
        resolved = %Events.ReportResolved{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          number: c.number,
          outcome: c.outcome
        }

        if c.outcome == "strike",
          do: [resolved, strike(c, strikes + 1)],
          else: resolved
    end
  end

  defp strike(c, number) do
    %Events.StrikeIssued{
      actor: c.actor,
      at: c.at,
      id: c.id,
      number: number,
      report: c.number,
      witness_account_id: c.witness_account_id,
      consequence: if(number >= 3, do: "removal", else: "fine")
    }
  end

  def apply(%__MODULE__{} = g, %Events.ReportFiled{} = e),
    do: %{g | id: e.id, count: e.number, reports: Map.put(g.reports, e.number, :open)}

  def apply(%__MODULE__{} = g, %Events.InvestigationStepRecorded{}), do: g

  def apply(%__MODULE__{} = g, %Events.ReportResolved{} = e),
    do: %{g | reports: Map.put(g.reports, e.number, :resolved)}

  def apply(%__MODULE__{} = g, %Events.StrikeIssued{} = e), do: %{g | strikes: e.number}

  defp text_ok?(text),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= @text_limit
end
