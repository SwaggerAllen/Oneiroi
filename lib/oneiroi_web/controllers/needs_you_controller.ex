defmodule OneiroiWeb.NeedsYouController do
  @moduledoc """
  `needs_you` (spec §5, brain#65): everything waiting on the witness's
  decision across the systems, oldest first, each naming the screen
  where it is decided; and its other side, what waits on her (brain#76).
  Reads only: nothing here decides anything.
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

  operation(:waiting_on_her,
    summary:
      "What waits on her (brain#76), oldest first: your proposals she has not answered, your letters unread, the files your lease holds her from; each entry's kind, its number, ref or path, a title, since when, the screen it lives on, and whether it has waited long",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the entries", "application/json", %Schema{type: :array}}]
  )

  def waiting_on_her(conn, %{"id" => id}), do: json(conn, Oneiroi.Brain.waiting_on_her(id))

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
