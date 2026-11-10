defmodule OneiroiWeb.ResidentChannel do
  @moduledoc """
  A resident's change notices (apsu#24): `resident:<resident_id>`, joined
  by a witness of that resident on the one socket. The join answers the
  store's head `position`; with a `since` cursor it first hands back what
  was missed, as one `notices` push, or `reset` when the gap is too wide
  to replay. After that each projected change arrives as a `notice`:
  `{kind, stream, ref, position}`, never the record itself.
  """
  use Phoenix.Channel

  alias Oneiroi.Apsu.Notices
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Gaia.Principal

  @impl Phoenix.Channel
  def join("resident:" <> resident_id, params, socket) do
    %Principal{account_id: account_id} = socket.assigns.principal

    if resident_id in Oneiroi.Gaia.witnessed_residents(account_id) do
      :ok = PubSub.subscribe(:apsu, :notices)
      if is_integer(params["since"]), do: send(self(), {:replay, params["since"]})
      {:ok, %{position: Notices.head()}, assign(socket, :resident_id, resident_id)}
    else
      {:error, %{reason: "not witnessed"}}
    end
  end

  @impl Phoenix.Channel
  def handle_info({:replay, since}, socket) do
    case Notices.since(socket.assigns.resident_id, since) do
      {:ok, notices} -> push(socket, "notices", %{notices: notices})
      :reset -> push(socket, "reset", %{position: Notices.head()})
    end

    {:noreply, socket}
  end

  def handle_info({:oneiroi, _topic, _payload, _trace} = envelope, socket) do
    resident_id = socket.assigns.resident_id

    case PubSub.receive(envelope) do
      {^resident_id, notice} -> push(socket, "notice", notice)
      _another_resident -> :ok
    end

    {:noreply, socket}
  end
end
