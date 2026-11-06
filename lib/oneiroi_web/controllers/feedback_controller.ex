defmodule OneiroiWeb.FeedbackController do
  @moduledoc """
  Platform reports (gaia#20): a person files one and follows their own;
  the operator lists, reads and moves them, a report's trace id pulling
  the matching entries from the failure ring (apsu#23) into the same
  view, so the reporter's words and the platform's facts sit together.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Apsu.Ops
  alias Oneiroi.Gaia
  alias OpenApiSpex.Schema

  tags(["feedback"])

  plug(:operator when action in [:index, :show, :move])

  operation(:create,
    summary:
      "File a platform report, a bug or a feature request, to the platform team (the operator's triage list and the triage resident)",
    request_body:
      {"the report", "application/json",
       %Schema{
         type: :object,
         required: [:kind, :body],
         properties: %{
           kind: %Schema{type: :string, enum: ~w(bug feature_request)},
           surface: %Schema{type: :string},
           body: %Schema{type: :string},
           trace_id: %Schema{type: :string}
         }
       }},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def create(conn, params) do
    attrs = %{
      kind: params["kind"],
      surface: params["surface"],
      body: params["body"],
      trace_id: params["trace_id"]
    }

    case Gaia.file_feedback(attrs, actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:mine,
    summary:
      "The platform reports this account filed or its residents did, newest first, with their status",
    responses: [ok: {"reports", "application/json", %Schema{type: :array}}]
  )

  def mine(%{assigns: %{principal: p}} = conn, _params),
    do: json(conn, Enum.map(Gaia.feedback_for_account(p.account_id), &row/1))

  operation(:index,
    summary: "Every platform report, newest first, narrowed by kind and status (the operator's)",
    parameters: [kind: [in: :query, type: :string], status: [in: :query, type: :string]],
    responses: [ok: {"reports", "application/json", %Schema{type: :array}}]
  )

  def index(conn, params),
    do:
      json(
        conn,
        Enum.map(Gaia.feedback(%{kind: params["kind"], status: params["status"]}), &row/1)
      )

  operation(:show,
    summary: "One platform report, with the failure ring's entries for its trace id",
    parameters: [number: [in: :path, type: :integer]],
    responses: [ok: {"the report", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"number" => number}) do
    case Gaia.feedback_report(integer(number)) do
      nil ->
        problem(
          conn,
          404,
          :no_such_report,
          :web_feedback_show_absent,
          "no report has that number"
        )

      f ->
        failures = if f.trace_id, do: Ops.failures(%{trace_id: f.trace_id}), else: []
        json(conn, Map.put(row(f), :failures, failures))
    end
  end

  operation(:move,
    summary:
      "Move a platform report's status (new, in_work, resolved, closed) with a note the reporter reads",
    parameters: [number: [in: :path, type: :integer]],
    request_body:
      {"the move", "application/json",
       %Schema{
         type: :object,
         required: [:status, :note],
         properties: %{status: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [no_content: "moved"]
  )

  def move(conn, %{"number" => number} = params) do
    case Gaia.move_feedback(integer(number), params["status"], params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, %{kind: :gaia_no_such_feedback} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp row(f),
    do:
      Map.take(f, [
        :number,
        :kind,
        :surface,
        :body,
        :trace_id,
        :author_kind,
        :author_id,
        :account_id,
        :resident_id,
        :status,
        :note,
        :filed_at,
        :moved_at,
        :moved_by
      ])

  defp integer(n) when is_integer(n), do: n

  defp integer(n) do
    case Integer.parse(to_string(n)) do
      {i, ""} -> i
      _ -> 0
    end
  end

  defp operator(%{assigns: %{principal: %{account_id: id}}} = conn, _opts) when is_binary(id) do
    if Gaia.operator?(id), do: conn, else: refuse(conn)
  end

  defp operator(conn, _opts), do: refuse(conn)

  defp refuse(conn),
    do:
      conn
      |> problem(
        403,
        :not_an_operator,
        :web_feedback_not_operator,
        "only a super admin reads the triage list"
      )
      |> halt()
end
