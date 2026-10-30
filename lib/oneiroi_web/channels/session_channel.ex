defmodule OneiroiWeb.SessionChannel do
  @moduledoc """
  The streamed conversation (spec §5): `session:<resident_id>:<key>`. A
  witness joins a session of a resident they witness; `send` runs a turn
  on the brain's session process and the reply arrives as `delta`
  events, then `turn` with the captured messages, or `stopped` with the
  honest notice, or `failed`.
  """
  use Phoenix.Channel

  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Gaia.Principal

  @impl Phoenix.Channel
  def join("session:" <> rest, _params, socket) do
    %Principal{account_id: account_id} = socket.assigns.principal

    with [resident_id, key] <- String.split(rest, ":", parts: 2),
         true <- resident_id in Oneiroi.Gaia.witnessed_residents(account_id) do
      :ok = PubSub.subscribe(:brain, :session)
      {:ok, assign(socket, resident_id: resident_id, session_key: key)}
    else
      _ -> {:error, %{reason: "not witnessed"}}
    end
  end

  @impl Phoenix.Channel
  def handle_in("send", %{"text" => text}, socket) when is_binary(text) do
    %{resident_id: resident_id, session_key: key, principal: principal} = socket.assigns
    actor = Principal.actor(principal)
    # Off the channel process, so deltas push while the turn runs; the
    # outcome arrives on the topic like every other event of the turn.
    Task.start(fn -> Oneiroi.Brain.turn(resident_id, key, text, actor) end)
    {:reply, :ok, socket}
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

  defp push_event(socket, {:delta, turn_ref, text}),
    do: push(socket, "delta", %{turn_ref: turn_ref, text: text})

  defp push_event(socket, {:turn, turn_ref, turn}),
    do: push(socket, "turn", Map.put(turn, :turn_ref, turn_ref))

  defp push_event(socket, {:failed, turn_ref, reason}),
    do: push(socket, "failed", %{turn_ref: turn_ref, reason: reason})

  defp push_event(_socket, _other), do: :ok
end
