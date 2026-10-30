defmodule Oneiroi.Ethos.Edge do
  @moduledoc """
  The command edge the seeds and the habits share: the dispatch with its
  translation of the aggregate's refusals, and the check that a
  citation's target exists in memory. Its own module because habits
  reach seeds (a habit's definition graduates its seed) and seeds would
  otherwise reach habits for these, which is the runtime cycle the
  cycles gate refuses.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Ethos.Error
  alias Oneiroi.Ethos.Router
  alias Oneiroi.Kumbukumbu

  # A bookmark is memory's row; its existence is checked at the command
  # edge, since the aggregate no longer sees memory's state (P38).
  @doc "Whether a citation's target exists: a turn by ref, or a bookmark by number in memory."
  def target_exists(resident_id, "bookmark", target_id) do
    with {:ok, number} <- integer(target_id),
         {:ok, _b, _span} <- Kumbukumbu.bookmark(resident_id, number) do
      :ok
    else
      _other -> {:error, Error.new(:ethos_target_invalid, kind: "bookmark", id: target_id)}
    end
  end

  def target_exists(_resident_id, "turn", target_id) when is_binary(target_id), do: :ok

  # A graduation toward a soul line names a live line of the soul file
  # (agathos-daimon #27); a position cannot be checked the same way, since
  # judgement reads this system and not the reverse.
  def target_exists(resident_id, "soul", target_id) do
    with {:ok, number} <- integer(target_id),
         %{} <- Enum.find(AgathosDaimon.soul_lines(resident_id), &(&1.number == number)) do
      :ok
    else
      _other -> {:error, Error.new(:ethos_target_invalid, kind: "soul", id: target_id)}
    end
  end

  def target_exists(_resident_id, kind, target_id),
    do: {:error, Error.new(:ethos_target_invalid, kind: kind, id: target_id)}

  defp integer(n) when is_integer(n), do: {:ok, n}

  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _other -> :error
    end
  end

  defp integer(_other), do: :error

  @doc "Dispatches to the character aggregate, translating its refusals into this system's errors."
  def dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} -> {:ok, events}
      {:error, reason} -> {:error, translate(reason, command)}
    end
  end

  defp translate(:no_such_habit, c), do: Error.new(:ethos_no_such_habit, number: c.number)
  defp translate(:name_invalid, _c), do: Error.new(:ethos_name_invalid)
  defp translate(:stance_invalid, _c), do: Error.new(:ethos_stance_invalid)
  defp translate(:trigger_invalid, _c), do: Error.new(:ethos_trigger_invalid)
  defp translate(:no_such_seed, c), do: Error.new(:ethos_no_such_seed, number: c.number)
  defp translate(:seed_closed, c), do: Error.new(:ethos_seed_closed, number: c.number)
  defp translate(:text_invalid, _c), do: Error.new(:ethos_seed_text_invalid)
  defp translate(:graduation_invalid, _c), do: Error.new(:ethos_graduation_invalid)
  defp translate(:baseline_fresh, _c), do: Error.new(:ethos_baseline_fresh)

  defp translate(:target_invalid, c),
    do: Error.new(:ethos_target_invalid, kind: c.target_kind, id: c.target_id)

  defp translate({:unconfirmed, days, required}, _c),
    do: Error.new(:ethos_unconfirmed, days: days, required: required)

  defp translate(other, _c), do: other
end
