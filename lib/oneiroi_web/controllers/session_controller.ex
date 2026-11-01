defmodule OneiroiWeb.SessionController do
  use OneiroiWeb, :controller

  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia.Error, as: IdentityError
  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:create,
    summary: "Log in: open a session",
    request_body:
      {"credentials", "application/json",
       %Schema{
         type: :object,
         required: [:email, :password],
         properties: %{
           email: %Schema{type: :string},
           password: %Schema{type: :string},
           code: %Schema{
             type: :string,
             description: "the TOTP code, once a second factor is enrolled"
           }
         }
       }},
    responses: [
      created: {"the principal", "application/json", %Schema{type: :object}},
      unauthorized: {"refused", "application/json", %Schema{type: :object}},
      service_unavailable:
        {"verified, but the session could not be opened; retry", "application/json",
         %Schema{type: :object}}
    ]
  )

  def create(conn, %{"email" => email, "password" => password} = params) do
    # Wrapped here, at the edge, so no frame between this line and the
    # password check holds them plain (a crash report prints a frame's
    # arguments; conventions §10).
    code = params["code"] && Secret.wrap(params["code"])

    case Oneiroi.Gaia.login(email, Secret.wrap(password), code) do
      {:ok, raw, principal} ->
        conn
        |> put_session(:sid, raw)
        |> put_status(201)
        |> json(%{account_id: principal.account_id, email: principal.email})

      {:error, :gaia_second_factor_required} ->
        error(conn, 401, IdentityError.new(:gaia_second_factor_required))

      {:error, :gaia_session_unavailable} ->
        conn
        |> put_resp_header("retry-after", "5")
        |> error(503, IdentityError.new(:gaia_session_unavailable))

      {:error, _reason} ->
        error(conn, 401, IdentityError.new(:gaia_invalid_credentials))
    end
  end

  def create(conn, _params),
    do: problem(conn, 422, :credentials_required, "email and password are required")

  operation(:delete, summary: "Log out: close the session", responses: [no_content: "closed"])

  def delete(conn, _params) do
    with raw when is_binary(raw) <- get_session(conn, :sid) do
      Oneiroi.Gaia.logout(raw)
    end

    conn |> configure_session(drop: true) |> send_resp(204, "")
  end
end
