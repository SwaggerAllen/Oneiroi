defmodule Oneiroi.Gaia.Handlers.Stewardship do
  @moduledoc """
  The cross-system effect that keeps stewardship in step with the
  resident (conventions §7): a resident created under a steward starts
  that stewardship; custody transferred to another account ends one and
  starts another. Eventual, through an event handler rather than a
  second command from the caller, and replay-safe because the account
  aggregate's start and end are idempotent.
  """
  use Commanded.Event.Handler,
    application: Oneiroi.Commanded,
    name: "gaia_stewardship",
    consistency: :strong

  alias Oneiroi.AgathosDaimon.Events.{CustodyTransferred, ResidentCreated}
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Router

  @impl Commanded.Event.Handler
  def init(config) do
    Oneiroi.Scope.put(:platform)
    {:ok, config}
  end

  @impl Commanded.Event.Handler
  def handle(%ResidentCreated{} = e, _metadata) do
    dispatch(%Commands.StartStewardship{
      actor: e.actor,
      at: e.at,
      id: e.steward_account_id,
      resident_id: e.id
    })
  end

  def handle(%CustodyTransferred{} = e, _metadata) do
    with :ok <- end_if_account(e.from, e), do: start_if_account(e.to, e)
  end

  defp end_if_account({:account, id}, e),
    do: dispatch(%Commands.EndStewardship{actor: e.actor, at: e.at, id: id, resident_id: e.id})

  defp end_if_account(_other, _e), do: :ok

  defp start_if_account({:account, id}, e),
    do: dispatch(%Commands.StartStewardship{actor: e.actor, at: e.at, id: id, resident_id: e.id})

  defp start_if_account(_other, _e), do: :ok

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, _events} -> :ok
      {:error, :no_such_account} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
