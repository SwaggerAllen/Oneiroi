defmodule Oneiroi.Sunna.BackfillWorker do
  @moduledoc "One pass of one day of the memory backfill (sunna#59): `Oneiroi.Sunna.Backfill.run/1`."
  use Oneiroi.Worker, queue: :sunna_backfill, max_attempts: 1

  alias Oneiroi.Sunna.Backfill

  def run(args), do: Backfill.run(args)
end
