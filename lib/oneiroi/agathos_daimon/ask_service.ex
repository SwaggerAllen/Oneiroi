defmodule Oneiroi.AgathosDaimon.AskService do
  @moduledoc """
  The command edge and reads for the resident's asks of her witness
  (agathos-daimon#35): she asks, he answers, the list both read.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AsksRouter
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc "She asks: kind `tool` or `act`, what, and why. Returns the ask's number."
  def ask(resident_id, kind, subject, why, %Actor{} = actor) do
    command = %Commands.MakeAsk{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      kind: kind,
      subject: subject,
      why: why
    }

    case dispatch(command) do
      {:ok, [event]} ->
        {:ok, event.number}

      {:ok, []} ->
        {:error, Error.new(:agathos_daimon_ask_invalid, :agathos_daimon_ask_not_recorded)}

      other ->
        other
    end
  end

  @doc "He answers: approve or decline an act, noted for a tool, with a note."
  def answer(resident_id, number, decision, note, %Actor{} = actor) do
    command = %Commands.AnswerAsk{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      decision: decision,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Every ask, newest first, with its answer when it has one."
  def asks(resident_id) do
    Scope.resident(resident_id, fn ->
      Repo.all(from(a in Store.Ask, order_by: [desc: a.number]))
    end)
    |> Enum.map(
      &Map.take(&1, [:number, :kind, :subject, :why, :asked_at, :decision, :note, :answered_at])
    )
  end

  defp dispatch(command) do
    case AsksRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(
           :agathos_daimon_dispatch_failed,
           :agathos_daimon_asks_dispatch_failed,
           reason
         )}
    end
  end
end
