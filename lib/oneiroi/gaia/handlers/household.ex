defmodule Oneiroi.Gaia.Handlers.Household do
  @moduledoc """
  Keeps every account and every resident inside a household (gaia#17,
  "never neither"): an account created founds its own household; a
  resident created joins its witness's; a resident whose custody moves to
  another account leaves the old household, with a note, and joins the
  new one's. Custody to the community leaves the resident where it was:
  the household that held it is still the last to have.

  Eventual, through an event handler (conventions §7), and replay-safe
  because the household's commands are idempotent. A new handler starts
  from the log's origin, so the accounts and residents that came before
  the household are given theirs on first boot.
  """
  use Commanded.Event.Handler,
    application: Oneiroi.Commanded,
    name: "gaia_household_members",
    consistency: :strong

  require Logger

  alias Oneiroi.AgathosDaimon.Custody
  alias Oneiroi.AgathosDaimon.Events.{CustodyTransferred, ResidentCreated}
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events.AccountCreated
  alias Oneiroi.Gaia.HouseholdRouter
  alias Oneiroi.Gaia.Households

  @impl Commanded.Event.Handler
  def init(config) do
    Oneiroi.Scope.put(:platform)
    {:ok, config}
  end

  @impl Commanded.Event.Handler
  def handle(%AccountCreated{} = e, _metadata) do
    dispatch(%Commands.FoundHousehold{actor: e.actor, at: e.at, id: e.id, account_id: e.id})
  end

  def handle(%ResidentCreated{} = e, _metadata) do
    dispatch(%Commands.JoinHouseholdResident{
      actor: e.actor,
      at: e.at,
      id: Households.household_id(e.witness_account_id),
      resident_id: e.id
    })
  end

  def handle(%CustodyTransferred{} = e, _metadata) do
    case {Custody.from_wire(e.from), Custody.from_wire(e.to)} do
      {from, {:account, to}} ->
        with :ok <- leave(from, e) do
          dispatch(%Commands.JoinHouseholdResident{
            actor: e.actor,
            at: e.at,
            id: Households.household_id(to),
            resident_id: e.id
          })
        end

      _to_the_community ->
        :ok
    end
  end

  defp leave({:account, from}, e),
    do:
      dispatch(%Commands.LeaveHouseholdResident{
        actor: e.actor,
        at: e.at,
        id: Households.household_id(from),
        resident_id: e.id,
        note: "custody moved to another account"
      })

  defp leave(_from, _e), do: :ok

  # Waits for the household's projection alone. A strong dispatch would
  # wait on every strong handler, this one and the witnessing handler
  # among them, and the two, each mid-event, would wait on each other
  # until the consistency timeout.
  defp dispatch(command) do
    case HouseholdRouter.dispatch(command, consistency: ["gaia_household"]) do
      {:ok, _events} -> :ok
      # A resident rebuilt from a repository arrives under the witness it
      # had where it came from, an account this platform may not hold;
      # the rebuild's custody transfer then places it with the importer.
      {:error, %{kind: :gaia_no_such_household}} -> :ok
      # The event is written; only the wait for the projection ran out.
      # On first boot the projection replays the log from its origin
      # beside this handler, and every backfilled household waited the
      # full timeout and was logged as a failure that was not one
      # (2026-11-05). The projection folds it when it catches up.
      {:error, :consistency_timeout} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Any other refusal is said and the event passed over, never a stop: a
  # handler that stops is restarted onto the same event until the
  # supervisor gives up, and the application goes down with it.
  @impl Commanded.Event.Handler
  def error({:error, reason}, event, _failure_context) do
    failure =
      case reason do
        %Error{} -> reason
        other -> Error.caught(:gaia_dispatch_failed, :gaia_household_handler_failed, other)
      end

    Logger.error(
      "gaia: a household membership was not recorded for #{inspect(event.__struct__)}",
      [component: "gaia"] ++ Oneiroi.Error.metadata(failure)
    )

    :skip
  end
end
