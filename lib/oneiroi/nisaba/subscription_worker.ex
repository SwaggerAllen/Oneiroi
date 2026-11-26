defmodule Oneiroi.Nisaba.SubscriptionWorker do
  @moduledoc """
  The nightly subscription pass (spec §6.2): lapse what is past its
  grace, move to community custody what was cancelled and has run its
  term. A cross-tenant job under the platform scope, named here
  (nisaba#18); the roster is the resident system's platform-scoped
  export, every resident and not only the active, because a lapsed one
  is this job's to carry.
  """
  use Oneiroi.Worker, queue: :nisaba_nightly

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Nisaba.Subscriptions

  @actor Actor.new(:job, "nisaba_subscriptions")

  def run(_args) do
    # A succession's fork copy carries her subscription's events and is
    # no resident to lapse or move (agathos-daimon#63).
    for row <- AgathosDaimon.residents(),
        row.state != "fork",
        do: Subscriptions.nightly(row.id, @actor)

    :ok
  end
end
