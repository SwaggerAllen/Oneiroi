defmodule OneiroiWeb.OperatorController do
  @moduledoc """
  The operator's surface (gaia#16): the front door and the platform roles.
  A super admin reads and changes both; anyone else is told the route is
  not theirs. The aggregate checks the authority again on every change.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Gaia
  alias OpenApiSpex.Schema

  tags(["operator"])

  plug(:operator)

  operation(:show,
    summary: "The front door (closed, invite or open) and every platform role held",
    responses: [ok: {"the platform", "application/json", %Schema{type: :object}}]
  )

  def show(conn, _params) do
    roles =
      for r <- Gaia.roles() do
        %{
          account_id: r.account_id,
          email: Gaia.account_email(r.account_id),
          role: r.role,
          note: r.note,
          granted_by: r.granted_by,
          granted_at: r.granted_at
        }
      end

    json(conn, %{gate: Gaia.gate(), roles: roles})
  end

  operation(:set_gate,
    summary: "Set the front door: closed, invite (the alpha) or open, with a note",
    request_body:
      {"the gate", "application/json",
       %Schema{
         type: :object,
         required: [:state, :note],
         properties: %{state: %Schema{type: :string}, note: %Schema{type: :string}}
       }},
    responses: [ok: {"the gate", "application/json", %Schema{type: :object}}]
  )

  def set_gate(conn, params) do
    case Gaia.set_gate(params["state"], params["note"], actor(conn)) do
      :ok -> json(conn, Gaia.gate())
      {:error, e} -> error(conn, 422, e)
    end
  end

  operation(:grant,
    summary:
      "Grant a platform role (super_admin or admin) to the account with that email, with a note",
    request_body:
      {"the grant", "application/json",
       %Schema{
         type: :object,
         required: [:email, :role, :note],
         properties: %{
           email: %Schema{type: :string},
           role: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "granted"]
  )

  def grant(conn, params) do
    with id when is_binary(id) <- Gaia.account_id_for(to_string(params["email"] || "")),
         :ok <- Gaia.grant_role(id, params["role"], params["note"], actor(conn)) do
      send_resp(conn, 204, "")
    else
      {:error, e} ->
        error(conn, 422, e)

      _none ->
        problem(
          conn,
          404,
          :no_such_account,
          :web_operator_grant_no_account,
          "no account has that email"
        )
    end
  end

  operation(:revoke,
    summary: "Revoke a platform role, with a note; never the last super admin",
    request_body:
      {"the revocation", "application/json",
       %Schema{
         type: :object,
         required: [:account_id, :role, :note],
         properties: %{
           account_id: %Schema{type: :string},
           role: %Schema{type: :string},
           note: %Schema{type: :string}
         }
       }},
    responses: [no_content: "revoked"]
  )

  def revoke(conn, params) do
    case Gaia.revoke_role(params["account_id"], params["role"], params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp operator(%{assigns: %{principal: %{account_id: id}}} = conn, _opts) when is_binary(id) do
    if Gaia.operator?(id),
      do: conn,
      else:
        conn
        |> problem(
          403,
          :not_an_operator,
          :web_operator_not_operator,
          "only a super admin reaches the operator's surface"
        )
        |> halt()
  end

  defp operator(conn, _opts),
    do:
      conn
      |> problem(
        403,
        :not_an_operator,
        :web_operator_not_operator,
        "only a super admin reaches the operator's surface"
      )
      |> halt()
end
