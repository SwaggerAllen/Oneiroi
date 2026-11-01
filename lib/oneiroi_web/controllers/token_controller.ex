defmodule OneiroiWeb.TokenController do
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:create,
    summary: "Issue an API token for scripts; the token is shown once",
    request_body:
      {"label", "application/json",
       %Schema{type: :object, required: [:label], properties: %{label: %Schema{type: :string}}}},
    responses: [created: {"the token and its hash", "application/json", %Schema{type: :object}}]
  )

  def create(%{assigns: %{principal: p}} = conn, %{"label" => label}) when is_binary(label) do
    case Oneiroi.Gaia.issue_token(p.account_id, label, actor(conn)) do
      {:ok, raw, hash} ->
        conn |> put_status(201) |> json(%{token: raw, hash: hash, label: label})

      {:error, reason} ->
        problem(conn, 422, :not_issued, :web_token_create_not_issued, inspect(reason))
    end
  end

  def create(conn, _params),
    do:
      problem(conn, 422, :label_required, :web_token_create_label_required, "a label is required")

  operation(:delete,
    summary: "Revoke a token by its hash",
    parameters: [hash: [in: :path, type: :string]],
    responses: [no_content: "revoked"]
  )

  def delete(%{assigns: %{principal: p}} = conn, %{"hash" => hash}) do
    case Oneiroi.Gaia.revoke_token(p.account_id, hash, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, _reason} ->
        problem(
          conn,
          404,
          :no_such_token,
          :web_token_delete_no_such_token,
          "no live token has that hash"
        )
    end
  end
end
