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

  operation(:invites,
    summary:
      "Every invite code issued, newest first, with its standing, and the default SKU; never a code",
    responses: [ok: {"the invites", "application/json", %Schema{type: :object}}]
  )

  def invites(conn, _params),
    do: json(conn, %{invites: Gaia.invites(), defaults: Gaia.invite_defaults()})

  operation(:issue_invite,
    summary:
      "Issue an invite code: a SKU (plan, list price in cents, discount, days of terms, uses, expiry), with a note. The code is answered once.",
    request_body:
      {"the SKU", "application/json",
       %Schema{
         type: :object,
         required: [:note],
         properties: %{
           plan: %Schema{type: :string},
           price_cents: %Schema{type: :integer},
           discount_pct: %Schema{type: :integer},
           term_days: %Schema{type: :integer},
           uses: %Schema{type: :integer},
           expires_at: %Schema{type: :string, format: :"date-time"},
           note: %Schema{type: :string}
         }
       }},
    responses: [
      created: {"the code, shown this once", "application/json", %Schema{type: :object}}
    ]
  )

  def issue_invite(conn, params) do
    with {:ok, sku} <- sku(params),
         {:ok, issued} <- Gaia.issue_invite(sku, params["note"], actor(conn)) do
      conn |> put_status(201) |> json(issued)
    else
      :bad_expiry ->
        problem(
          conn,
          422,
          :invalid,
          :web_operator_invite_expiry,
          "expires_at is an ISO 8601 instant"
        )

      {:error, e} ->
        error(conn, 422, e)
    end
  end

  operation(:revoke_invite,
    summary: "Revoke an invite code, with a note",
    request_body:
      {"the note", "application/json",
       %Schema{type: :object, required: [:note], properties: %{note: %Schema{type: :string}}}},
    responses: [no_content: "revoked"]
  )

  def revoke_invite(conn, %{"id" => id} = params) do
    case Gaia.revoke_invite(id, params["note"], actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  # The SKU's fields the operator named; the rest are the defaults.
  defp sku(params) do
    named =
      %{
        plan: params["plan"],
        price_nanos: params["price_cents"] && params["price_cents"] * 10_000_000,
        discount_pct: params["discount_pct"],
        term_days: params["term_days"],
        uses: params["uses"]
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    case params["expires_at"] do
      blank when blank in [nil, ""] ->
        {:ok, named}

      text when is_binary(text) ->
        case DateTime.from_iso8601(text) do
          {:ok, at, _offset} -> {:ok, Map.put(named, :expires_at, at)}
          _bad -> :bad_expiry
        end

      _other ->
        :bad_expiry
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
