defmodule OneiroiWeb.KindController do
  @moduledoc """
  Her document kinds, as the witness keeps them beside her (seshat#51):
  every kind with its gate and which are hers, and the gate proposals; a
  kind of hers defined or rewritten, a system kind's gate moved, a gate
  proposal of hers answered. A gate goes on at once; off is a proposal
  the other party answers.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary:
      "Every kind her library has, the system's and hers, with its gate, and the gate proposals",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the kinds", "application/json", %Schema{type: :object}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, Seshat.user_kinds(id))

  operation(:define,
    summary:
      "Define or rewrite a kind of hers; its descriptor is checked against the safe subset and written into its folder",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the kind", "application/json",
       %Schema{
         type: :object,
         required: [:kind],
         properties: %{
           kind: %Schema{type: :string},
           label: %Schema{type: :string},
           cites: %Schema{type: :boolean},
           has_status: %Schema{type: :boolean},
           removable: %Schema{type: :boolean},
           approvable: %Schema{type: :boolean},
           ask: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [created: {"the kind", "application/json", %Schema{type: :object}}]
  )

  def define(conn, %{"id" => id} = params) do
    attrs =
      params
      |> Map.take(~w(kind label cites has_status removable approvable))
      |> Map.put("approval", %{"ask" => params["ask"]})

    case Seshat.define_kind(id, attrs, params["note"], actor(conn)) do
      {:ok, kind} -> conn |> put_status(201) |> json(%{kind: kind})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:gate,
    summary: "Move a system kind's gate: on at once, off as a proposal she answers",
    parameters: [id: [in: :path, type: :string], kind: [in: :path, type: :string]],
    request_body:
      {"the gate", "application/json",
       %Schema{
         type: :object,
         required: [:approvable],
         properties: %{approvable: %Schema{type: :boolean}, note: %Schema{type: :string}}
       }},
    responses: [ok: {"moved, proposed or already so", "application/json", %Schema{type: :object}}]
  )

  def gate(conn, %{"id" => id, "kind" => kind} = params) do
    case Seshat.kind_gate(id, kind, params["approvable"] == true, params["note"], actor(conn)) do
      {:ok, outcome} -> json(conn, %{outcome: outcome})
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:answer,
    summary: "Answer her gate proposal: agree or decline, with a note",
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
         :ok <-
           Seshat.answer_kind_gate(id, n, params["agree"] == true, params["note"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      {:error, e} ->
        error(conn, 422, e)

      _bad ->
        problem(
          conn,
          422,
          :number_invalid,
          :web_kind_number_invalid,
          "the proposal's number is a whole number"
        )
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
            :agathos_daimon_web_kinds_not_witnessed
          )
        )
        |> halt()
  end
end
