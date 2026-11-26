defmodule Oneiroi.Brain.SuccessionWake do
  @moduledoc """
  A succession's wake (brain#122): the resident woken in her main
  conversation with a note from Janus (a judge's runs ready to judge,
  the deliberation's rounds, the farewell's wakes), answered as a turn
  billed under `succession`. Janus reaches it through its brain port,
  since the brain depends on Janus for her tools.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.Session
  alias Oneiroi.Kumbukumbu

  @actor Actor.new(:job, "janus")

  @doc "Wakes `resident_id` in her main conversation with `note`."
  @spec wake(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def wake(resident_id, note) do
    with {:ok, row} <- fetch(resident_id),
         {:ok, key} <- Kumbukumbu.main_session(resident_id, row.account_id, @actor) do
      admitted(resident_id, key, note)
    end
  end

  # The same admission every wake passes (`Oneiroi.Brain.wake/4`), then
  # the session's own wake.
  defp admitted(resident_id, key, note) do
    case AgathosDaimon.admission(resident_id) do
      :open ->
        Session.wake(resident_id, key, note, :succession, [])

      admission ->
        {:error,
         Error.new(:brain_resident_guarded, :brain_succession_wake_guarded, admission: admission)}
    end
  end

  defp fetch(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} ->
        {:ok, row}

      :error ->
        {:error,
         Error.new(:brain_no_such_resident, :brain_succession_wake_absent,
           resident_id: resident_id
         )}
    end
  end
end
