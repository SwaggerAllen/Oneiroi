defmodule Oneiroi.Sunna.QueueState do
  @moduledoc """
  Whether a household's house queue runs (sunna#94), read alone: the
  work loop asks it and the queue's service writes it, so the read
  stands apart from both. The cutover (sunna#80) is history since the
  old work queue retired (sunna#102): the queue runs unless paused.
  """

  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.QueueStore.State

  @doc "The queue's state row, or a fresh one before any."
  def get(household_id) do
    Scope.platform(fn -> Repo.get_by(State, household_id: household_id) end) ||
      %State{household_id: household_id, cut_over: false}
  end

  @doc "Whether the house queue runs (sunna#94, #102): unless paused."
  def running?(nil), do: false
  def running?(household_id), do: get(household_id).paused != true
end
