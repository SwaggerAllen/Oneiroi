defmodule OneiroiWeb.ThemeController do
  @moduledoc """
  Her theme (seshat#56): the three seeds the client derives the screen's
  colours from, `THEME.md` at her root, the witness's to set; and her
  proposals, which he accepts or declines with a note. A set or a
  proposal the readability checks refuse is answered 422 with the checks.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  @seeds %Schema{
    type: :object,
    required: [:ground, :resident, :witness],
    properties: %{
      ground: %Schema{type: :string, pattern: "^#[0-9a-fA-F]{6}$"},
      resident: %Schema{type: :string, pattern: "^#[0-9a-fA-F]{6}$"},
      witness: %Schema{type: :string, pattern: "^#[0-9a-fA-F]{6}$"},
      note: %Schema{type: :string}
    }
  }

  operation(:show,
    summary:
      "The theme: the three seeds (from THEME.md, or the default until it exists), the readability checks on them, and her proposals with his answers",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the theme", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id}), do: json(conn, Seshat.theme(id))

  operation(:update,
    summary:
      "Set the three seeds, with a note: checked for readability and written as THEME.md; an unreadable set is refused 422 with the checks",
    parameters: [id: [in: :path, type: :string]],
    request_body: {"the seeds", "application/json", @seeds},
    responses: [ok: {"the theme", "application/json", %Schema{type: :object}}]
  )

  def update(conn, %{"id" => id} = params) do
    case Seshat.set_theme(
           id,
           Map.take(params, ~w(ground resident witness)),
           params["note"],
           actor(conn)
         ) do
      {:ok, theme} -> json(conn, theme)
      {:error, e} -> refused(conn, e)
    end
  end

  operation(:answer,
    summary:
      "Answer her theme proposal: accept (THEME.md takes its seeds) or decline, with a note; she is told by a letter",
    parameters: [id: [in: :path, type: :string], number: [in: :path, type: :integer]],
    request_body:
      {"the answer", "application/json",
       %Schema{
         type: :object,
         required: [:agree, :note],
         properties: %{agree: %Schema{type: :boolean}, note: %Schema{type: :string}}
       }},
    responses: [ok: {"the theme", "application/json", %Schema{type: :object}}]
  )

  def answer(conn, %{"id" => id, "number" => number} = params) do
    with {n, ""} <- Integer.parse(to_string(number)),
         :ok <- Seshat.answer_theme(id, n, params["agree"] == true, params["note"], actor(conn)) do
      json(conn, Seshat.theme(id))
    else
      {:error, e} ->
        refused(conn, e)

      _bad ->
        problem(
          conn,
          422,
          :number_invalid,
          :web_theme_number_invalid,
          "the proposal's number is a whole number"
        )
    end
  end

  # The envelope, and for an unreadable set the checks that refused it,
  # so the editor can say which.
  defp refused(conn, %{kind: :seshat_theme_unreadable, details: details} = e) do
    checks = Keyword.get(List.wrap(details), :checks, [])

    conn
    |> put_status(422)
    |> json(%{
      error: %{
        kind: Atom.to_string(e.kind),
        site: Atom.to_string(e.site),
        meaning: e.meaning,
        remedy: e.remedy,
        checks: checks
      }
    })
  end

  defp refused(conn, e), do: error(conn, 422, e)

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_theme_not_witnessed
          )
        )
        |> halt()
  end
end
