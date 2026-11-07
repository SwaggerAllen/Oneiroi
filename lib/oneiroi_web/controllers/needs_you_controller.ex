defmodule OneiroiWeb.NeedsYouController do
  @moduledoc """
  `needs_you` (spec §5, brain#65): everything waiting on the witness's
  decision across the systems, oldest first, each naming the screen
  where it is decided. A read only: nothing here decides anything.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary:
      "What waits on you, oldest first: each entry's kind, its number or path, since when, the screen it is decided on, and whether it has waited long",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the entries", "application/json", %Schema{type: :array}}]
  )

  def index(conn, %{"id" => id}), do: json(conn, Oneiroi.Brain.needs_you(id))

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_needs_you_not_witnessed
          )
        )
        |> halt()
  end
end
