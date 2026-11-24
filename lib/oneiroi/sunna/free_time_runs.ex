defmodule Oneiroi.Sunna.FreeTimeRuns do
  @moduledoc """
  Whether her free time is live (sunna#96): a run since `since` with no
  closing turn recorded counts only while it began in the last minutes,
  or its conversation has a turn open or had one in the last minutes. A run that went quiet without
  its closing turn is over, whatever the record lacks. Read by the work
  loop's care rule and by the letter wake, which joins a live pass rather
  than starting a second.
  """

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Sunna.Store

  @quiet 15 * 60

  @doc "Whether a free-time pass of hers begun since `since` is still going."
  @spec live?(String.t(), DateTime.t()) :: boolean()
  def live?(resident_id, since) do
    resident_id
    |> then(&Scope.resident(&1, fn -> Store.free_time_unclosed(since) end))
    |> Enum.any?(fn {key, at} -> recent?(at) or session_live?(resident_id, key) end)
  end

  # A run just begun is live before its first turn is captured.
  defp recent?(%DateTime{} = at), do: DateTime.diff(Clock.now(), at, :second) < @quiet
  defp recent?(_at), do: false

  defp session_live?(resident_id, key) do
    case Kumbukumbu.uncompacted(resident_id, key) do
      {:ok, %{open_turn_ref: ref}, _count} when is_binary(ref) ->
        true

      {:ok, %{last_turn_at: %DateTime{} = last}, _count} ->
        DateTime.diff(Clock.now(), last, :second) < @quiet

      _gone ->
        false
    end
  end
end
