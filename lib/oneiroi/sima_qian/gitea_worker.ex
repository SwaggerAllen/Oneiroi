defmodule Oneiroi.SimaQian.GiteaWorker do
  @moduledoc """
  Sends one repository to Gitea (sima-qian#55, #56): a household's after
  its writes, a resident's after its backup. One job per repository while
  one waits; a write during a push asks for the next. A push that fails
  is retried by the queue, and a repository Gitea refuses waits there,
  never the write that asked.
  """
  use Oneiroi.Worker,
    queue: :sima_qian_gitea,
    unique: [period: 300, keys: [:household_id, :resident_id], states: [:available, :scheduled]]

  alias Oneiroi.SimaQian.Gitea

  def run(%{"household_id" => id}), do: done(Gitea.sync_household(id))
  def run(%{"resident_id" => id}), do: done(Gitea.sync_resident(id))

  defp done({:ok, _}), do: :ok
  defp done(:ok), do: :ok
  defp done({:error, _} = failed), do: failed
end
