defmodule OneiroiWeb.BackfillController do
  @moduledoc """
  The memory backfill (sunna#59), the witness's to start and stop: Lily
  writes the scenes, names the domains and runs the people pass for each
  past day in a range, oldest first, one pass a job.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias OpenApiSpex.Schema

  tags(["schedule"])

  plug(:witnessed)

  operation(:show,
    summary:
      "Where the memory backfill is: the day and pass it runs or waits on, its last day and the domain lists; null when none runs",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"status", "application/json", %Schema{type: :object, nullable: true}}]
  )

  def show(conn, %{"id" => id}), do: json(conn, Oneiroi.Sunna.backfill_status(id))

  operation(:start,
    summary:
      "Start the memory backfill over a range of past days (sunna#59): scenes, then domains named from his list and hers, then the people pass, a day at a time; a running one is replaced",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the range and lists", "application/json",
       %Schema{
         type: :object,
         required: [:from, :to],
         properties: %{
           from: %Schema{type: :string, description: "YYYY-MM-DD"},
           to: %Schema{type: :string, description: "YYYY-MM-DD, before today"},
           his: %Schema{type: :array, items: %Schema{type: :string}},
           hers: %Schema{type: :array, items: %Schema{type: :string}}
         }
       }},
    responses: [created: {"the days", "application/json", %Schema{type: :object}}]
  )

  def start(conn, %{"id" => id} = params) do
    case Oneiroi.Sunna.backfill_start(
           id,
           params["from"],
           params["to"],
           Map.take(params, ["his", "hers"]),
           actor(conn)
         ) do
      {:ok, days} -> conn |> put_status(201) |> json(%{days: days})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:stop,
    summary: "Stop the memory backfill; a turn already running finishes",
    parameters: [id: [in: :path, type: :string]],
    responses: [no_content: "stopped"]
  )

  def stop(conn, %{"id" => id}) do
    :ok = Oneiroi.Sunna.backfill_stop(id)
    send_resp(conn, 204, "")
  end

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_backfill_not_witnessed
          )
        )
        |> halt()
  end
end
