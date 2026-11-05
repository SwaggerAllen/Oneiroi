defmodule OneiroiWeb.DoorController do
  @moduledoc """
  The front door from outside (gaia#19), open to anyone: what state the
  door is in, whether a code would let someone in (without spending it),
  and sign-up, which opens a session on the new account as logging in
  does.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia
  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:show,
    summary: "The front door's state: closed, invite or open",
    responses: [ok: {"the door", "application/json", %Schema{type: :object}}]
  )

  def show(conn, _params), do: json(conn, %{state: Gaia.gate().state})

  operation(:check,
    summary: "What an invite code would grant, or why it would not; the code is not spent",
    request_body:
      {"the code", "application/json",
       %Schema{type: :object, required: [:code], properties: %{code: %Schema{type: :string}}}},
    responses: [ok: {"the terms it would grant", "application/json", %Schema{type: :object}}]
  )

  def check(conn, %{"code" => code}) when is_binary(code) do
    case Gaia.check_invite(code) do
      {:ok, sku} -> json(conn, sku)
      {:error, e} -> error(conn, 422, e)
    end
  end

  def check(conn, _params),
    do: problem(conn, 422, :code_required, :web_door_check_code_required, "code is required")

  operation(:sign_up,
    summary:
      "Sign up behind the door: closed refuses, invite takes a code, open takes anyone; opens a session",
    request_body:
      {"the account", "application/json",
       %Schema{
         type: :object,
         required: [:email, :password],
         properties: %{
           email: %Schema{type: :string},
           password: %Schema{type: :string},
           code: %Schema{
             type: :string,
             description: "the invite code; required while the door is invite"
           }
         }
       }},
    responses: [
      created: {"the new account, logged in", "application/json", %Schema{type: :object}}
    ]
  )

  def sign_up(conn, %{"email" => email, "password" => password} = params)
      when is_binary(email) and is_binary(password) do
    # Wrapped at the edge, as logging in does (conventions §10).
    secret = Secret.wrap(password)

    with {:ok, id} <- Gaia.sign_up(email, secret, params["code"]),
         {:ok, raw, principal} <- Gaia.login(email, secret, nil) do
      conn
      |> put_session(:sid, raw)
      |> put_status(201)
      |> json(%{account_id: id, email: principal.email})
    else
      {:error, %{kind: :gaia_door_closed} = e} -> error(conn, 403, e)
      {:error, %{kind: :gaia_email_taken} = e} -> error(conn, 409, e)
      {:error, e} -> error(conn, 422, e)
    end
  end

  def sign_up(conn, _params),
    do:
      problem(
        conn,
        422,
        :credentials_required,
        :web_door_sign_up_credentials_required,
        "email and password are required"
      )
end
