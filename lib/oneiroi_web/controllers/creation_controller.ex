defmodule OneiroiWeb.CreationController do
  @moduledoc "The creation flow's gifts (agathos-daimon#36): their order, what each writes, and the guidance read before each; and the example sets beside them (agathos-daimon#41)."
  use OneiroiWeb, :controller

  alias OpenApiSpex.Schema

  tags(["resident"])

  operation(:gifts,
    summary:
      "The nine gifts in order, each with what it writes and the guidance the witness reads first",
    responses: [ok: {"gifts", "application/json", %Schema{type: :array}}]
  )

  def gifts(conn, _params), do: json(conn, Oneiroi.AgathosDaimon.gifts())

  operation(:examples,
    summary:
      "The example sets for the gifts' files (agathos-daimon#41): each set's prompt and its files in the gifts' order; [] when none is committed",
    responses: [ok: {"example sets", "application/json", %Schema{type: :array}}]
  )

  def examples(conn, _params), do: json(conn, Oneiroi.AgathosDaimon.gift_examples())
end
