defmodule OneiroiWeb.ReactController do
  @moduledoc """
  The witness's reacts (kumbukumbu#56): an emoji on a reply of hers or a
  letter, which wakes nothing and is told on her next turn; the reacts
  as the transcript shows them; and the vocabulary, `REACTIONS.md` at
  her repository's root, read as the palette and written by either
  party.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Brain
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["resident"])

  plug(:witnessed)

  operation(:index,
    summary:
      "The reacts, oldest first, each with its target and whether it was told her; one conversation's with `session_key`, one document's with `path` (kumbukumbu#61)",
    parameters: [
      id: [in: :path, type: :string],
      session_key: [in: :query, type: :string],
      path: [in: :query, type: :string]
    ],
    responses: [ok: {"the reacts", "application/json", %Schema{type: :array}}]
  )

  def index(conn, %{"id" => id} = params) do
    opts =
      [session_key: params["session_key"], path: params["path"]]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    json(
      conn,
      for r <- Kumbukumbu.reacts(id, opts) do
        %{
          number: r.number,
          target_kind: r.target_kind,
          session_key: r.session_key,
          turn_ref: r.turn_ref,
          letter: r.letter,
          path: r.path,
          document_hash: r.document_hash,
          emoji: r.emoji,
          by: r.by,
          reacted_at: r.reacted_at,
          told_at: r.told_at
        }
      end
    )
  end

  operation(:react,
    summary:
      "React on a reply of hers (`target: {kind: message, session_key, turn_ref}`), a letter (`{kind: letter, number}`) or a document (`{kind: document, path}`, kumbukumbu#61, the version it holds now recorded); it wakes nothing",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the react", "application/json",
       %Schema{
         type: :object,
         required: [:target, :emoji],
         properties: %{target: %Schema{type: :object}, emoji: %Schema{type: :string}}
       }},
    responses: [created: {"its number", "application/json", %Schema{type: :object}}]
  )

  def react(conn, %{"id" => id} = params) do
    case react_on(id, params["target"], params["emoji"], actor(conn)) do
      {:ok, n} -> conn |> put_status(201) |> json(%{number: n})
      {:error, e} -> error(conn, 422, e)
    end
  end

  # A document is resolved by the library, which hashes the words it
  # holds now (kumbukumbu#61); the rest are the reacts ledger's to check.
  defp react_on(id, %{"kind" => "document", "path" => path}, emoji, actor) when is_binary(path),
    do: Seshat.react_document(id, path, emoji, actor)

  defp react_on(id, target, emoji, actor), do: Kumbukumbu.react(id, target, emoji, actor)

  operation(:vocabulary,
    summary:
      "The reacts' vocabulary: each emoji with its meaning, from REACTIONS.md, or the seed until it exists",
    parameters: [id: [in: :path, type: :string]],
    responses: [ok: {"the pairs", "application/json", %Schema{type: :array}}]
  )

  def vocabulary(conn, %{"id" => id}),
    do: json(conn, for({e, m} <- Brain.react_vocabulary(id), do: %{emoji: e, meaning: m}))

  operation(:set_vocabulary,
    summary: "Write the reacts' vocabulary as REACTIONS.md",
    parameters: [id: [in: :path, type: :string]],
    request_body:
      {"the pairs", "application/json",
       %Schema{type: :object, required: [:pairs], properties: %{pairs: %Schema{type: :array}}}},
    responses: [no_content: "written"]
  )

  def set_vocabulary(conn, %{"id" => id} = params) do
    pairs =
      for %{"emoji" => e, "meaning" => m} <- List.wrap(params["pairs"]),
          is_binary(e) and is_binary(m),
          do: {String.trim(e), String.trim(m)}

    case Brain.set_react_vocabulary(id, pairs, actor(conn)) do
      :ok -> send_resp(conn, 204, "")
      {:error, e} -> error(conn, 422, e)
    end
  end

  defp witnessed(%{params: %{"id" => id}} = conn, _opts) do
    if witnesses?(conn, id),
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_reacts_not_witnessed
          )
        )
        |> halt()
  end
end
