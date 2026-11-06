defmodule OneiroiWeb.WaitingController do
  @moduledoc """
  What waits for an adapter (kumbukumbu#48, the one wake contract): the
  platform cannot reach a runtime it does not run, so each runtime asks
  here, cheaply and often, and wakes its model only when something new
  waits. A `brain` adapter is told the house letters waiting for the
  conversation it names (`session_key`); a `reader` adapter, the approved
  replies it has to send, the research questions open (seshat#38) and
  the digest asked (seshat#40).
  Numbers and who they are from or for, never
  their words, and nothing is marked read: the letter is read with
  letter_inbox, the reply with the reader's own route. A witness may ask
  too, and is told all of it.
  """
  use OneiroiWeb, :controller

  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.AgathosDaimon.Error, as: ResidentError
  alias Oneiroi.Apsu.Ops
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Xenia
  alias OpenApiSpex.Schema

  tags(["adapters"])

  plug(:allowed)

  operation(:show,
    summary:
      "What waits for this adapter: house letters for its conversation (a brain adapter, with `session_key`), approved replies to send (a reader); numbers and senders, never words, nothing marked read",
    parameters: [
      id: [in: :path, type: :string],
      session_key: [in: :query, type: :string, required: false]
    ],
    responses: [ok: {"what waits", "application/json", %Schema{type: :object}}]
  )

  def show(conn, %{"id" => id} = params) do
    role = role(conn)

    # The adapter's heartbeat (apsu#23): it asked, now.
    case conn.assigns[:principal] do
      %AdapterPrincipal{adapter: name} ->
        Ops.beat("#{id}:#{name}")

      _witness ->
        :ok
    end

    letters =
      if role in ["brain", :witness] and is_binary(params["session_key"]),
        do: Enum.map(Kumbukumbu.inbox(id, params["session_key"]), &letter/1),
        else: []

    replies =
      if role in ["reader", :witness],
        do: Enum.map(Xenia.replies(id, "approved"), &%{number: &1.number, platform: &1.platform}),
        else: []

    research =
      if role in ["reader", :witness],
        do: Enum.map(Seshat.researches(id, status: "open"), &%{number: &1.number}),
        else: []

    digests =
      if role in ["reader", :witness],
        do: Enum.map(Seshat.digests(id, status: "open"), &%{number: &1.number}),
        else: []

    # The writing gate (seshat#42): approved pieces to draft and drafted
    # ones to watch, by path alone.
    pieces =
      if role in ["reader", :witness] do
        %{to_draft: draft, to_watch: watch} = Seshat.pieces_for_reader(id)

        Enum.map(draft, &%{path: &1.path, step: "draft"}) ++
          Enum.map(watch, &%{path: &1.path, step: "watch"})
      else
        []
      end

    json(conn, %{
      letters: letters,
      replies: replies,
      research: research,
      digests: digests,
      pieces: pieces
    })
  end

  defp letter(l), do: %{number: l.number, from: l.from_name, in_reply_to: l.in_reply_to}

  defp role(conn) do
    case adapter(conn) do
      %AdapterPrincipal{role: role} -> role
      nil -> :witness
    end
  end

  defp allowed(%{params: %{"id" => id}} = conn, _opts) do
    ok? =
      case adapter(conn) do
        %AdapterPrincipal{resident_id: ^id} -> true
        %AdapterPrincipal{} -> false
        nil -> witnesses?(conn, id)
      end

    if ok?,
      do: conn,
      else:
        conn
        |> error(
          404,
          ResidentError.new(
            :agathos_daimon_not_witnessed,
            :agathos_daimon_web_waiting_not_witnessed
          )
        )
        |> halt()
  end
end
