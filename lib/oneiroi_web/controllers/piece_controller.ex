defmodule OneiroiWeb.PieceController do
  @moduledoc """
  The writing gate, the witness's side (seshat#42): the pieces she marked
  for review, and his approve or decline with a note, which reaches her
  free time as a letter. An approved piece goes to the reader, which
  makes a Substack draft; he presses Publish there.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["library"])

  plug(:witnessed)

  operation(:index,
    summary: "Pieces for review, approved (the reader drafts), and drafted (publish on Substack)",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"pieces", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, Seshat.pieces(id))

  operation(:review,
    summary: "Approve or decline a piece marked for review, with a note",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the review", "application/json",
       %Schema{
         type: :object,
         required: [:path, :decision, :note],
         properties: %{
           path: %Schema{type: :string},
           decision: %Schema{type: :string, enum: ~w(approve decline)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "reviewed"]
  )

  def review(conn, %{"id" => id} = params) do
    path = to_string(params["path"] || "")

    case Seshat.review_piece(id, path, params["decision"], params["note"], actor(conn)) do
      :ok ->
        tell(id, path, params["decision"], params["note"], actor(conn))
        send_resp(conn, 204, "")

      {:error, %{kind: :seshat_no_such_document} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  defp tell(id, path, decision, note, actor) do
    next =
      if decision == "approve",
        do: "The reader will make a Substack draft of it, and he publishes it from there.",
        else: "It stays yours to rework; mark it for review again when it is ready."

    text = "Your witness #{decision}d #{path}. His note: #{note} #{next}"
    _ = Oneiroi.Kumbukumbu.send_letter(id, nil, %{to: "Free time", text: text}, actor)
    :ok
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
            :agathos_daimon_web_piece_not_witnessed
          )
        )
        |> halt()
  end
end
