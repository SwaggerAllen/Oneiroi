defmodule Oneiroi.AgathosDaimon.PluginService do
  @moduledoc """
  The command edge and reads for plugins (agathos-daimon#37): a change
  proposed and answered, an installable plugin switched off by either
  party, the carry-over, and the state both parties read. The catalog
  (which plugins exist, of which tier) is the brain's; this is the
  contract's record of what was agreed.
  """

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.PluginsRouter
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc "Proposes a change to a plugin, with its why; the proposal's number."
  def propose(resident_id, key, tier, change, note, %Actor{} = actor) do
    command = %Commands.ProposePlugin{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      tier: tier,
      change: change,
      note: note
    }

    with {:ok, [event]} <- dispatch(command), do: {:ok, event.number}
  end

  @doc "The other party answers a proposal, agreed or declined, with a note."
  def answer(resident_id, number, agree, note, %Actor{} = actor) do
    command = %Commands.AnswerPlugin{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      number: number,
      agree: agree == true,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc "Either party switches an installable plugin off at once, with a note."
  def switch_off(resident_id, key, tier, note, %Actor{} = actor) do
    command = %Commands.SwitchPluginOff{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      key: key,
      tier: tier,
      note: note
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  The keys of the plugins installed and on. The first time a resident's
  plugins are read, the slots that existed before plugins (`carried`)
  are recorded as carried over, once; a slot added later is not among
  them, and waits for both parties.
  """
  def on_keys(resident_id, carried) do
    rows = states(resident_id)

    rows =
      if rows == [] and carried != [] do
        _ =
          dispatch(%Commands.CarryOverPlugins{
            actor: Actor.platform(),
            at: Clock.now(),
            id: resident_id,
            keys: carried
          })

        states(resident_id)
      else
        rows
      end

    for %{installed: true, on: true, key: key} <- rows, do: key
  end

  @doc "The keys installed and on, read only: a resident never read before reads as carried over, and nothing is recorded (a trial, a preview)."
  def on_keys_read(resident_id, carried) do
    case states(resident_id) do
      [] -> carried
      rows -> for %{installed: true, on: true, key: key} <- rows, do: key
    end
  end

  @doc "Each plugin's state, by key."
  def states(resident_id),
    do: Scope.resident(resident_id, fn -> Repo.all(from(p in Store.Plugin, order_by: p.key)) end)

  @doc "Every proposal, newest first, with its answer when it has one."
  def proposals(resident_id),
    do:
      Scope.resident(resident_id, fn ->
        Repo.all(from(p in Store.PluginProposal, order_by: [desc: p.number]))
      end)

  defp dispatch(command) do
    case PluginsRouter.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error,
         Error.caught(
           :agathos_daimon_dispatch_failed,
           :agathos_daimon_plugins_dispatch_failed,
           reason
         )}
    end
  end
end
