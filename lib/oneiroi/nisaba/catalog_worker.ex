defmodule Oneiroi.Nisaba.CatalogWorker do
  @moduledoc """
  The catalog's nightly fetch (nisaba#24): the provider's list, priced,
  replacing the last. A failed fetch keeps the old list and is retried
  by the job's attempts; the next night fetches again either way.
  """
  use Oneiroi.Worker, queue: :nisaba_nightly, max_attempts: 3

  alias Oneiroi.Nisaba.Catalog

  def run(_args), do: with({:ok, _count} <- Catalog.refresh(), do: :ok)
end
