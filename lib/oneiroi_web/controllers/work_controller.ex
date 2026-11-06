defmodule OneiroiWeb.WorkController do
  @moduledoc """
  The work queue (sunna#33), as the witness keeps it beside her: the
  list and the loop's state, an item of his own added, a status moved
  with a note, the order changed. His items enter it the same as hers.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Sunna
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary:
      "The work queue: items in priority order with status and last wrap, and the loop's state",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the queue", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, Sunna.work_queue(id))

  operation(:create,
    summary: "Add an item to the end of the queue: what, and what done looks like",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the item", "application/json",
       %Schema{
         type: :object,
         required: [:what, :done_when],
         properties: %{what: %Schema{type: :string}, done_when: %Schema{type: :string}}
       }},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def create(conn, %{"id" => id} = params) do
    case Sunna.work_add(id, params["what"], params["done_when"], actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:move,
    summary: "Move an item's status with a note: open, blocked (on what), done or dropped",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the move", "application/json",
       %Schema{
         type: :object,
         required: [:status, :note],
         properties: %{
           status: %Schema{type: :string, enum: ~w(open blocked done dropped)},
           blocked_on: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "moved"]
  )

  def move(conn, %{"id" => id, "number" => number} = params) do
    with {n, ""} <- Integer.parse(to_string(number)),
         :ok <-
           Sunna.work_move(
             id,
             n,
             params["status"],
             params["blocked_on"],
             params["note"],
             actor(conn)
           ) do
      send_resp(conn, 204, "")
    else
      {:error, %{kind: :sunna_no_such_work} = e} -> error(conn, 404, e)
      {:error, e} -> error(conn, 422, e)
      _bad -> number_invalid(conn)
    end
  end

  operation(:order,
    summary: "Reorder the queue: the numbers given first, in that order",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the order", "application/json",
       %Schema{
         type: :object,
         required: [:order],
         properties: %{order: %Schema{type: :array, items: %Schema{type: :integer}}}
       }},
    responses: [no_content: "reordered"]
  )

  def order(conn, %{"id" => id} = params) do
    numbers = params["order"]

    if is_list(numbers) and Enum.all?(numbers, &is_integer/1) do
      case Sunna.work_order(id, numbers, actor(conn)) do
        :ok -> send_resp(conn, 204, "")
        {:error, e} -> error(conn, 422, e)
      end
    else
      number_invalid(conn)
    end
  end

  defp number_invalid(conn),
    do:
      problem(
        conn,
        422,
        :number_invalid,
        :web_work_number_invalid,
        "an item's number is a whole number"
      )

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(:agathos_daimon_not_witnessed, :agathos_daimon_web_work_not_witnessed)
        )
        |> halt()
  end
end
