defmodule Oneiroi.Seshat.IndexWorker do
  @moduledoc """
  The nightly index run (spec §6.7's nightly list: after the export):
  every active resident's library, a cross-tenant job under the
  platform scope, named here (seshat #17); the roster is the resident
  system's platform-scoped export. A resident whose run fails is
  recorded on its own run row and the pass goes on.
  """
  use Oneiroi.Worker, queue: :seshat_nightly

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Seshat.Index

  @actor Actor.new(:job, "seshat_nightly")

  def run(_args) do
    for row <- AgathosDaimon.active_residents(), do: Index.run(row.id, @actor)
    :ok
  end
end
