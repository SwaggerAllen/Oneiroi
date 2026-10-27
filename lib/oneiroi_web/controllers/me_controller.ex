defmodule OneiroiWeb.MeController do
  use OneiroiWeb, :controller

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
      residents: Oneiroi.Gaia.stewarded_residents(p.account_id)
    })
  end
end
