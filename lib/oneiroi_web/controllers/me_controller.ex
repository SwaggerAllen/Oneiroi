defmodule OneiroiWeb.MeController do
  use OneiroiWeb, :controller

  alias Oneiroi.Gaia.Error, as: IdentityError
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
      residents: Oneiroi.Gaia.stewarded_residents(p.account_id),
      key: Oneiroi.Gaia.key_status(p.account_id)
    })
  end

  operation(:store_key,
    summary:
      "Store the OpenRouter key every model call for this account's residents spends; storing again rotates it",
    request_body:
      {"the key", "application/json",
       %Schema{type: :object, required: [:key], properties: %{key: %Schema{type: :string}}}},
    responses: [no_content: "stored"]
  )

  def store_key(%{assigns: %{principal: p}} = conn, %{"key" => key}) do
    case Oneiroi.Gaia.store_key(p.account_id, key, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, :gaia_key_required} -> error(conn, 422, IdentityError.new(:gaia_key_required))
      {:error, reason} -> problem(conn, 422, :key_not_stored, inspect(reason))
    end
  end

  def store_key(conn, _params), do: problem(conn, 422, :key_required, "key is required")

  operation(:revoke_key, summary: "Revoke the stored key", responses: [no_content: "revoked"])

  def revoke_key(%{assigns: %{principal: p}} = conn, _params) do
    case Oneiroi.Gaia.revoke_key(p.account_id, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, :gaia_no_key} -> error(conn, 404, IdentityError.new(:gaia_no_key))
      {:error, reason} -> problem(conn, 422, :key_not_revoked, inspect(reason))
    end
  end
end
