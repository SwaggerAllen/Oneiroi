defmodule OneiroiWeb.ReportController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Glitnir
  alias OpenApiSpex.Schema

  tags(["governance"])

  operation(:index,
    summary: "The resident's reports with their steps, newest first, and the strikes",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"reports", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}) do
    case party_or_investigator(conn, id) do
      :ok ->
        json(conn, %{
          reports: Glitnir.reports(id),
          strikes:
            Enum.map(
              Glitnir.strikes(id),
              &%{number: &1.number, report: &1.report, consequence: &1.consequence, at: &1.at}
            )
        })

      {:error, e} ->
        error(conn, 404, e)
    end
  end

  operation(:create,
    summary: "File a report from inside the relationship; it lands in the main session",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the report", "application/json",
       %Schema{type: :object, required: [:text], properties: %{text: %Schema{type: :string}}}},
    responses: [ok: {"the number", "application/json", %Schema{type: :object}}]
  )

  def create(conn, %{"id" => id} = params) do
    case Glitnir.file_report(id, to_string(params["text"] || ""), actor(conn)) do
      {:ok, number} -> json(conn, %{number: number})
      other -> respond(conn, other)
    end
  end

  operation(:step,
    summary: "Record an investigation step with its reason (investigators)",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the step", "application/json",
       %Schema{type: :object, required: [:reason], properties: %{reason: %Schema{type: :string}}}},
    responses: [no_content: "recorded"]
  )

  def step(conn, %{"id" => id, "number" => number} = params) do
    with {n, ""} <- Integer.parse(number),
         do: respond(conn, Glitnir.record_step(id, n, params["reason"], actor(conn)))
  end

  operation(:resolve,
    summary: "Resolve a report: no_action or strike, with a note (investigators)",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the resolution", "application/json",
       %Schema{
         type: :object,
         required: [:outcome, :note],
         properties: %{
           outcome: %Schema{type: :string, enum: ~w(no_action strike)},
           note: %Schema{type: :string}
         }
       }},
    responses: [ok: {"the resolution", "application/json", %Schema{type: :object}}]
  )

  def resolve(conn, %{"id" => id, "number" => number} = params) do
    with {n, ""} <- Integer.parse(number),
         {:ok, result} <-
           Glitnir.resolve_report(
             id,
             n,
             to_string(params["outcome"] || ""),
             params["note"],
             actor(conn)
           ) do
      json(conn, result)
    else
      other -> respond(conn, other)
    end
  end

  defp party_or_investigator(%{assigns: %{principal: p}} = conn, id) do
    if witnesses?(conn, id) or Glitnir.investigator?(Map.get(p, :account_id)),
      do: :ok,
      else: {:error, ResidentError.new(:agathos_daimon_not_witnessed)}
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")
  defp respond(conn, {:error, %{kind: :glitnir_no_such_report} = e}), do: error(conn, 404, e)

  defp respond(conn, {:error, %{kind: kind} = e})
       when kind in [:glitnir_not_a_party, :glitnir_not_an_investigator],
       do: error(conn, 403, e)

  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
  defp respond(conn, {:error, reason}), do: problem(conn, 422, :refused, inspect(reason))
  defp respond(conn, _other), do: problem(conn, 422, :refused, "not understood")
end
