defmodule OneiroiWeb.SessionChannel do
  @moduledoc """
  The conversation's live events (spec §5): `session:<resident_id>:<key>`.
  A witness joins a session of a resident they witness and may read (a
  private session of hers is refused, as its transcript is); `send` runs
  a turn on the brain's session process, and the turn says it started,
  its step (`status`), then `turn` with the captured messages, or
  `failed`. Her reply is not streamed (brain#111; the witness,
  2026-11-21): it lands whole.
  """
  use Phoenix.Channel

  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Gaia.Principal

  @impl Phoenix.Channel
  def join("session:" <> rest, _params, socket) do
    %Principal{account_id: account_id} = socket.assigns.principal

    with [resident_id, key] <- String.split(rest, ":", parts: 2),
         true <- resident_id in Oneiroi.Gaia.witnessed_residents(account_id),
         {:ok, _session, _messages, _total} <-
           Oneiroi.Kumbukumbu.transcript_range({:account, account_id}, key, 0, 0) do
      :ok = PubSub.subscribe(:brain, :session)
      # What is generating now (brain#114), so a client joining mid-turn
      # shows it working and hears its end.
      {:ok, Oneiroi.Brain.working(resident_id, key),
       assign(socket, resident_id: resident_id, session_key: key)}
    else
      _ -> {:error, %{reason: "not witnessed"}}
    end
  end

  @impl Phoenix.Channel
  def handle_in("send", %{"text" => text} = params, socket) when is_binary(text) do
    %{resident_id: resident_id, session_key: key, principal: principal} = socket.assigns
    actor = Principal.actor(principal)
    # Taken by the session's queue (brain#45), which runs the turn off
    # this process; the outcome arrives on
    # the topic like every other event of the turn.
    ref = params["client_ref"] || Oneiroi.Kumbukumbu.turn_ref()

    case Oneiroi.Brain.submit(resident_id, key, text, actor, ref) do
      {:ok, taken} ->
        {:reply, {:ok, taken}, socket}

      {:error, %{kind: :brain_resident_guarded, meaning: meaning}} ->
        {:reply, {:error, %{reason: meaning}}, socket}

      {:error, _e} ->
        {:reply, {:error, %{reason: "the session could not take it"}}, socket}
    end
  end

  def handle_in("send", _params, socket),
    do: {:reply, {:error, %{reason: "text is required"}}, socket}

  @impl Phoenix.Channel
  def handle_info({:oneiroi, _topic, _payload, _trace} = envelope, socket) do
    %{resident_id: resident_id, session_key: key} = socket.assigns

    case PubSub.receive(envelope) do
      {^resident_id, ^key, payload} -> push_event(socket, payload)
      _other_session -> :ok
    end

    {:noreply, socket}
  end

  defp push_event(socket, {:turn_started, turn_ref}),
    do: push(socket, "turn_started", %{turn_ref: turn_ref})

  defp push_event(socket, {:turn, turn_ref, turn}),
    do: push(socket, "turn", Map.put(turn, :turn_ref, turn_ref))

  defp push_event(socket, {:status, turn_ref, state, detail}),
    do: push(socket, "status", %{turn_ref: turn_ref, state: state, detail: detail})

  defp push_event(socket, {:failed, turn_ref, reason}),
    do: push(socket, "failed", %{turn_ref: turn_ref, reason: reason})

  defp push_event(_socket, _other), do: :ok
end
