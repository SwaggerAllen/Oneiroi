defmodule OneiroiWeb.SecondFactorController do
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["identity"])

  operation(:create,
    summary: "Enroll a TOTP second factor; the secret is shown once",
    responses: [
      created: {"the secret and its otpauth URI", "application/json", %Schema{type: :object}}
    ]
  )

  def create(%{assigns: %{principal: p}} = conn, _params) do
    case Oneiroi.Gaia.enroll_second_factor(p.account_id, actor(conn)) do
      {:ok, %{secret: secret, uri: uri}} ->
        conn |> put_status(201) |> json(%{secret: secret, uri: uri})

      {:error, reason} ->
        problem(conn, 422, :not_enrolled, :web_second_factor_create_not_enrolled, inspect(reason))
    end
  end
end
