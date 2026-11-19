defmodule OneiroiWeb.UnreadController do
  @moduledoc """
  What the witness has not read yet, by workspace (gaia#58, seshat#96):
  each resident's Oneiroi chat, her messages after the witness's mark,
  and the house, posts by anyone else after the mark for each thread.
  The client marks as it shows; a first look sets the baseline, so the
  counts start from now rather than from all of history.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias OpenApiSpex.Schema

  tags(["unread"])

  operation(:index,
    summary:
      "The witness's unread by workspace (gaia#58): each resident's Oneiroi chat, her messages after the witness's mark; the house, others' posts after the mark for each thread",
    responses: [ok: {"unread", "application/json", %Schema{type: :object}}]
  )

  def index(%{assigns: %{principal: p}} = conn, _params) do
    actor = Actor.new(:witness, p.account_id)

    residents =
      for r <- AgathosDaimon.for_witness(p.account_id),
          {:ok, key} <- [Kumbukumbu.main_session(r.id, p.account_id, actor)],
          do: %{id: r.id, count: chat_unread(p.account_id, r.id, key, actor)}

    house =
      case Seshat.household_unread(actor) do
        {:ok, h} -> h
        {:error, _} -> nil
      end

    json(conn, %{residents: residents, house: house})
  end

  operation(:mark,
    summary:
      "Mark read up to an instant (gaia#58): subject `house` with a thread, or a resident's id for her Oneiroi chat",
    request_body:
      {"the mark", "application/json",
       %Schema{
         type: :object,
         required: [:subject, :at],
         properties: %{
           subject: %Schema{type: :string},
           thread: %Schema{type: :string},
           at: %Schema{type: :string}
         }
       }},
    responses: [no_content: "marked"]
  )

  def mark(%{assigns: %{principal: p}} = conn, params) do
    actor = Actor.new(:witness, p.account_id)

    with {:ok, at, _} <- DateTime.from_iso8601(to_string(params["at"] || "")),
         :ok <- mark(params["subject"], params["thread"], at, p.account_id, actor) do
      send_resp(conn, 204, "")
    else
      {:error, %{kind: _} = e} -> error(conn, 422, e)
      _bad -> error(conn, 422, Gaia.Error.new(:gaia_seen_invalid, :gaia_web_unread_mark_shape))
    end
  end

  defp mark("house", thread, at, _account_id, actor),
    do: Seshat.household_mark_seen(actor, thread, at)

  defp mark(resident_id, _thread, at, account_id, actor) when is_binary(resident_id) do
    with true <- Enum.any?(AgathosDaimon.for_witness(account_id), &(&1.id == resident_id)),
         {:ok, key} <- Kumbukumbu.main_session(resident_id, account_id, actor) do
      Gaia.mark_seen(account_id, resident_id, key, at, actor)
    else
      _not_hers -> {:error, Gaia.Error.new(:gaia_seen_invalid, :gaia_web_unread_mark_resident)}
    end
  end

  defp mark(_subject, _thread, _at, _account_id, _actor),
    do: {:error, Gaia.Error.new(:gaia_seen_invalid, :gaia_web_unread_mark_subject)}

  # Her chat: what she said after the mark, or after the baseline, set now
  # on a first look.
  defp chat_unread(account_id, resident_id, key, actor) do
    marks = Gaia.seen(account_id, resident_id)

    case Map.get(marks, key) || Map.get(marks, "*") do
      nil ->
        _ = Gaia.mark_seen(account_id, resident_id, "*", Clock.now(), actor)
        0

      since ->
        Kumbukumbu.said_after(resident_id, key, since)
    end
  end
end
