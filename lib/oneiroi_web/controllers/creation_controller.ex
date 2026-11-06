defmodule OneiroiWeb.CreationController do
  @moduledoc "The creation flow's gifts (agathos-daimon#36): their order, what each writes, and the guidance read before each."
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["resident"])

  operation(:gifts,
    summary:
      "The nine gifts in order, each with what it writes and the guidance the witness reads first",
    responses: [ok: {"gifts", "application/json", %Schema{type: :array}}]
  )

  def gifts(conn, _params), do: json(conn, Oneiroi.AgathosDaimon.gifts())
end
