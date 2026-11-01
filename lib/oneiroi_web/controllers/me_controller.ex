defmodule OneiroiWeb.MeController do
  use OneiroiWeb, :controller

  alias Oneiroi.Config.Secret
  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:show,
    summary: "The account behind this session or token",
    responses: [ok: {"the principal", "application/json", %Schema{type: :object}}]
  )

  def show(%{assigns: %{principal: p}} = conn, _params) do
    json(conn, %{
      account_id: p.account_id,
      email: p.email,
      via: Atom.to_string(p.via),
      residents: Oneiroi.Gaia.witnessed_residents(p.account_id),
      key: Oneiroi.Gaia.key_status(p.account_id)
    })
  end

  operation(:socket_token,
    summary: "A short-lived token the client opens the socket with",
    responses: [created: {"the token", "application/json", %Schema{type: :object}}]
  )

  def socket_token(%{assigns: %{principal: p}} = conn, _params) do
    conn |> put_status(201) |> json(%{token: OneiroiWeb.UserSocket.token(conn, p.account_id)})
  end

  operation(:store_key,
    summary:
      "Store the OpenRouter key every model call for this account's residents spends; storing again rotates it",
    request_body:
      {"the key", "application/json",
       %Schema{type: :object, required: [:key], properties: %{key: %Schema{type: :string}}}},
    responses: [no_content: "stored"]
  )

  def store_key(%{assigns: %{principal: p}} = conn, %{"key" => raw}) do
    key = Secret.wrap(raw)

    case Oneiroi.Gaia.store_key(p.account_id, key, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  def store_key(conn, _params),
    do: problem(conn, 422, :key_required, :web_me_store_key_key_required, "key is required")

  operation(:revoke_key, summary: "Revoke the stored key", responses: [no_content: "revoked"])

  def revoke_key(%{assigns: %{principal: p}} = conn, _params) do
    case Oneiroi.Gaia.revoke_key(p.account_id, actor(conn)) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, %{kind: :gaia_no_key} = e} ->
        error(conn, 404, e)

      {:error, e} ->
        error(conn, 422, e)
    end
  end
end
