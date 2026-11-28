defmodule OneiroiWeb.HouseChannel do
  @moduledoc """
  The household's change notices (sunna#80): `house:<household_id>`,
  joined by a witness of that household on the one socket. Each change
  the house queue's projection folds arrives as a `notice`
  (`{kind, stream, ref, position}`, never the record), so the Work page
  reads again when something moved and never on a timer.
  """
  use Phoenix.Channel

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Gaia.Principal

  # The household's streams a page here follows.
  # Its threads too (seshat#108): a thread written reads the shelf again.
  # Its charter, members and beats (`household`) and its rounds too (the
  # witness, 2026-11-26: pages are pushed to, not polled).
  @streams ["queue", "threads", "household", "rounds"]

  @impl Phoenix.Channel
  # `house:mine`, the caller's own household, for a page that does not
  # hold its id.
  def join("house:mine", params, socket) do
    %Principal{account_id: account_id} = socket.assigns.principal

    case Oneiroi.Gaia.household_of(Actor.new(:witness, account_id)) do
      household_id when is_binary(household_id) ->
        join("house:" <> household_id, params, socket)

      _none ->
        {:error, %{reason: "no household"}}
    end
  end

  def join("house:" <> household_id, _params, socket) do
    %Principal{account_id: account_id} = socket.assigns.principal

    if Oneiroi.Gaia.household_of(Actor.new(:witness, account_id)) == household_id do
      :ok = PubSub.subscribe(:apsu, :notices)
      {:ok, %{build: OneiroiWeb.ClientBuild.id()}, assign(socket, :household_id, household_id)}
    else
      {:error, %{reason: "not a member"}}
    end
  end

  @impl Phoenix.Channel
  def handle_info({:oneiroi, _topic, _payload, _trace} = envelope, socket) do
    household_id = socket.assigns.household_id

    case PubSub.receive(envelope) do
      {^household_id, %{stream: stream} = notice} when stream in @streams ->
        push(socket, "notice", notice)

      _other ->
        :ok
    end

    {:noreply, socket}
  end
end
