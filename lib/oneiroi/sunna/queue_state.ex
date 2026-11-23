defmodule Oneiroi.Sunna.QueueState do
  @moduledoc """
  Whether a household has cut over to the house queue (sunna#80, §6.2),
  read alone: the old work loop asks it, and the queue's service turns
  that loop off, so the read stands apart from both.
  """

  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.QueueStore.State

  @doc "The queue's state row, or a fresh one before any."
  def get(household_id) do
    Scope.platform(fn -> Repo.get_by(State, household_id: household_id) end) ||
      %State{household_id: household_id, cut_over: false}
  end

  @doc "Whether the household has cut over."
  def cut_over?(nil), do: false
  def cut_over?(household_id), do: get(household_id).cut_over == true
end
