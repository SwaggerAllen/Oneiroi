defmodule OneiroiWeb.WorkController do
  @moduledoc """
  The resident's work line (sunna#33, #86), as the witness keeps it
  beside her: what runs and why it rests, the runs given back, the
  free-time wait skipped. The old queue's items retired (sunna#102); her
  work is the house queue's.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Sunna
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary:
      "The work line: the activity running, why the line rests, the day's runs and each activity's (sunna#101), the last run cut off (sunna#100)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the queue", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}) do
    q = Sunna.work_queue(id)
    # Where the running turn is (brain#119): receipts, never words.
    json(conn, Map.put(q, :progress, q.running_key && Oneiroi.Brain.progress(id, q.running_key)))
  end

  operation(:reset_runs,
    summary:
      "Give the work runs back (sunna#53, #101): the day's count and each activity's start over and the loop checks at once; the witness's, with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "reset"]
  )

  def reset_runs(conn, %{"id" => id} = params) do
    case Sunna.work_reset_runs(id, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:skip_care,
    summary:
      "Skip the free-time wait (sunna#76): a free-time pass begun before now no longer holds the work line, and the loop checks at once; quiet hours still do; the witness's, with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "skipped"]
  )

  def skip_care(conn, %{"id" => id} = params) do
    case Sunna.work_skip_care(id, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:resume,
    summary:
      "Take up her work line after a stopped run (sunna#109): the stop rests it until resumed; the witness's, with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "resumed"]
  )

  def resume(conn, %{"id" => id} = params) do
    case Sunna.work_resume(id, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

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
