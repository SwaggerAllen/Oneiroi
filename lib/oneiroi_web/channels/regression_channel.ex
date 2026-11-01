defmodule OneiroiWeb.RegressionChannel do
  @moduledoc """
  A regression run as it answers (eunomia #30):
  `regression:<resident_id>:<run_ref>`. Joined by an account that
  witnesses the resident, the same check as `SessionChannel`; an
  adapter's token is never a witness, and the socket does not take one
  in the first place. It pushes `card`, in the blind shape the run's
  detail gives an unrevealed card, as each is recorded, and `finished`
  with the run's end (`finished` or `failed`) and its card count.
  Grading stays on the HTTP routes; nothing is received here.

  The unawareness invariant (spec §6.4) is unchanged by it: the topic's
  only subscriber is this channel, which only a witness joins.
  """
  use Phoenix.Channel

  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Gaia.Principal

  @impl Phoenix.Channel
  def join("regression:" <> rest, _params, socket) do
    with %Principal{account_id: account_id} <- socket.assigns.principal,
         [resident_id, run_ref] <- String.split(rest, ":", parts: 2),
         true <- resident_id in Oneiroi.Gaia.witnessed_residents(account_id) do
      :ok = PubSub.subscribe(:eunomia, :regression)
      {:ok, assign(socket, resident_id: resident_id, run_ref: run_ref)}
    else
      _ -> {:error, %{reason: "not witnessed"}}
    end
  end

  @impl Phoenix.Channel
  def handle_info({:oneiroi, _topic, _payload, _trace} = envelope, socket) do
    %{resident_id: resident_id, run_ref: run_ref} = socket.assigns

    case PubSub.receive(envelope) do
      {^resident_id, ^run_ref, {:card, card}} -> push(socket, "card", card)
      {^resident_id, ^run_ref, {:finished, ended}} -> push(socket, "finished", ended)
      _other_run -> :ok
    end

    {:noreply, socket}
  end
end
