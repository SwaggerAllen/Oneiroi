defmodule OneiroiWeb.AskController do
  @moduledoc """
  The resident's asks of her witness (agathos-daimon#35): the list, and
  his answer to one, which comes back to her free time as a letter.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary: "Her asks, newest first: a tool she lacked or leave for an act, why, and the answer",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"asks", "application/json", %Schema{type: :array}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, AgathosDaimon.asks(id))

  operation(:answer,
    summary:
      "Answer an ask with a note: approve or decline an act, noted for a tool; the answer reaches her free time as a letter",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the answer", "application/json",
       %Schema{
         type: :object,
         required: [:decision, :note],
         properties: %{
           decision: %Schema{type: :string, enum: ~w(approve decline noted)},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "answered"]
  )

  def answer(conn, %{"id" => id, "number" => number} = params) do
    with {n, ""} <- Integer.parse(to_string(number)),
         :ok <- AgathosDaimon.answer_ask(id, n, params["decision"], params["note"], actor(conn)) do
      tell(id, n, params["decision"], params["note"], actor(conn))
      send_resp(conn, 204, "")
    else
      {:error, %{kind: :agathos_daimon_no_such_ask} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)

      _bad ->
        problem(
          conn,
          422,
          :number_invalid,
          :web_ask_number_invalid,
          "the ask's number is a whole number"
        )
    end
  end

  # His answer reaches her where she asked: a letter to her free time,
  # which waits for the next slot when none is running.
  defp tell(id, n, decision, note, actor) do
    ask = Enum.find(AgathosDaimon.asks(id), &(&1.number == n))

    text =
      "Your witness answered your ask ##{n} (#{ask && ask.subject}): #{decision}. His note: #{note}"

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
          ResidentError.new(:agathos_daimon_not_witnessed, :agathos_daimon_web_ask_not_witnessed)
        )
        |> halt()
  end
end
