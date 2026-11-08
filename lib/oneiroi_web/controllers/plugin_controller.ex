defmodule OneiroiWeb.PluginController do
  @moduledoc """
  Plugins, as the witness keeps them beside the resident (brain#68,
  agathos-daimon#37): the catalog with her state and every proposal; a
  change proposed, a proposal of hers answered, an installable plugin
  switched off. Contract material: a memory slot moves only by a
  proposal the other party agrees.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Brain
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary:
      "The plugins her context is assembled from and any others she could hold, each with its state, and every proposal",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the plugins", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, Brain.plugins(id))

  operation(:propose,
    summary: "Propose a change to a plugin: install, remove, on or off, with why; she answers",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the proposal", "application/json",
       %Schema{
         type: :object,
         required: [:key, :change, :note],
         properties: %{
           key: %Schema{type: :string},
           change: %Schema{type: :string, enum: ~w(install remove on off)},
           note: %Schema{type: :string}
         }
       }},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def propose(conn, %{"id" => id} = params) do
    case Brain.propose_plugin(id, params["key"], params["change"], params["note"], actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:answer,
    summary: "Answer her plugin proposal: agree or decline, with a note",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the answer", "application/json",
       %Schema{
         type: :object,
         required: [:agree, :note],
         properties: %{agree: %Schema{type: :boolean}, note: %Schema{type: :string}}
       }},
    responses: [no_content: "answered"]
  )

  def answer(conn, %{"id" => id, "number" => number} = params) do
    with {n, ""} <- Integer.parse(to_string(number)),
         :ok <- Brain.answer_plugin(id, n, params["agree"] == true, params["note"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      {:error, e} ->
        error(conn, 422, e)

      _bad ->
        problem(
          conn,
          422,
          :number_invalid,
          :web_plugin_number_invalid,
          "the proposal's number is a whole number"
        )
    end
  end

  operation(:off,
    summary: "Switch an installable plugin off at once, with why: either party's alone",
    parameters: [id: [in: :path, type: :string], key: [in: :path, type: :string]],
    request_body:
      {"why", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "switched off"]
  )

  def off(conn, %{"id" => id, "key" => key} = params) do
    case Brain.switch_plugin_off(id, key, params["note"], actor(conn)) do
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
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_plugins_not_witnessed
          )
        )
        |> halt()
  end
end
