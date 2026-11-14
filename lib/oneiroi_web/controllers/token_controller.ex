defmodule OneiroiWeb.TokenController do
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:create,
    summary: "Issue an API token for scripts; the token is shown once",
    request_body:
      {"label", "application/json",
       %Schema{
         type: :object,
         required: [:label],
         properties: %{
           label: %Schema{type: :string},
           scope: %Schema{
             type: :string,
             enum: ["ops"],
             description:
               "ops: a token that reads GET /v1/ops/* and nothing else (gaia#40, apsu#30), a super admin's to mint; left out, the account's whole reach"
           }
         }
       }},
    responses: [created: {"the token and its hash", "application/json", %Schema{type: :object}}]
  )

  def create(%{assigns: %{principal: p}} = conn, %{"label" => label}) when is_binary(label) do
    case Oneiroi.Gaia.issue_token(p.account_id, label, actor(conn), scope: conn.params["scope"]) do
      {:ok, raw, hash} ->
        conn |> put_status(201) |> json(%{token: raw, hash: hash, label: label})

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def create(conn, _params),
    do:
      problem(conn, 422, :label_required, :web_token_create_label_required, "a label is required")

  operation(:index,
    summary:
      "The account's tokens, newest first: label, hash, scope, when issued and revoked; never the token itself",
    responses: [ok: {"tokens", "application/json", %Schema{type: :array}}]
  )

  def index(%{assigns: %{principal: p}} = conn, _params),
    do: json(conn, Oneiroi.Gaia.tokens(p.account_id))

  operation(:delete,
    summary: "Revoke a token by its hash",
    parameters: [hash: [in: :path, type: :string]],
    responses: [no_content: "revoked"]
  )

  def delete(%{assigns: %{principal: p}} = conn, %{"hash" => hash}) do
    case Oneiroi.Gaia.revoke_token(p.account_id, hash, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, e} ->
        error(conn, 404, e)
    end
  end
end
