defmodule OneiroiWeb.JournalController do
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["library"])

  plug(:witnessed)

  operation(:index,
    summary: "The journal's latest days with their plan-versus-actuals deltas, newest first",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"days", "application/json", %Schema{type: :array}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, Seshat.journal_days(id, 30))

  operation(:show,
    summary: "One day: its row, its entries in order, its delta",
    parameters: [id: [in: :path, type: :string], day: [in: :path, type: :string]],
    responses: [ok: {"the day", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id, "day" => day}) do
    case Seshat.journal_day(id, day) do
      nil ->
        error(
          conn,
          404,
          Seshat.Error.new(:seshat_no_such_day, :seshat_journal_controller_day_absent, day: day)
        )

      %{entries: entries} = d ->
        json(conn, %{d | entries: Enum.map(entries, &entry/1)})
    end
  end

  operation(:add,
    summary: "Add an entry to a day: plan, note, todo or wrap",
    parameters: [id: [in: :path, type: :string], day: [in: :path, type: :string]],
    request_body:
      {"the entry", "application/json",
       %Schema{
         type: :object,
         required: [:kind, :text],
         properties: %{
           kind: %Schema{type: :string, enum: ~w(plan note todo wrap)},
           text: %Schema{type: :string}
         }
       }},
    responses: [ok: {"the entry's number", "application/json", %Schema{type: :object}}]
  )

  def add(conn, %{"id" => id, "day" => day} = params) do
    case Seshat.journal_add(
           id,
           day,
           params["kind"],
           to_string(params["text"] || ""),
           params["register"],
           actor(conn)
         ) do
      {:ok, result} -> json(conn, result)
      other -> respond(conn, other)
    end
  end

  operation(:done,
    summary: "Mark a todo done",
    parameters: [
      id: [in: :path, type: :string],
      day: [in: :path, type: :string],
      number: [in: :path, type: :integer]
    ],
    responses: [no_content: "done"]
  )

  def done(conn, %{"id" => id, "day" => day, "number" => number}) do
    case Integer.parse(number) do
      {n, ""} ->
        respond(conn, Seshat.journal_done(id, day, n, actor(conn)))

      _other ->
        error(
          conn,
          404,
          Seshat.Error.new(:seshat_no_such_todo, :seshat_journal_controller_todo_absent,
            day: day,
            number: number
          )
        )
    end
  end

  defp entry(e),
    do: %{
      number: e.number,
      kind: e.kind,
      register: e.register,
      text: e.text,
      at: e.at,
      by: e.actor_kind,
      done_at: e.done_at
    }

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_journal_not_witnessed
          )
        )
        |> halt()
  end

  defp respond(conn, :ok), do: send_resp(conn, 204, "")
  defp respond(conn, {:error, %{kind: :seshat_no_such_todo} = e}), do: error(conn, 404, e)
  defp respond(conn, {:error, %{kind: _} = e}), do: error(conn, 422, e)
end
