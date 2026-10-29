defmodule Oneiroi.Proteus.CardAuditWorker do
  @moduledoc """
  The weekly card audit (spec §6.9): for every active resident with a
  workspace, pin the card back from git if a dream moved it. A
  cross-tenant job under the platform scope, named here (proteus #11);
  the roster is the resident system's platform-scoped export.
  """
  use Oneiroi.Worker, queue: :proteus_weekly

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Proteus.Bridges

  @actor Actor.new(:job, "proteus_card_audit")

  def run(_args) do
    for row <- AgathosDaimon.active_residents(), Bridges.bridge(row.id) != nil do
      Bridges.audit_card(row.id, @actor)
    end

    :ok
  end
end
