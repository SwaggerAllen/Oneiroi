defmodule Oneiroi.Brain.Retry do
  @moduledoc """
  A failed turn run again (brain#89; the witness, 2026-11-13: "errors
  like that should always come with an action the user can take other
  than dismiss, so missing free time should allow free time to fire off
  immediately"). A capture failure records its conversation, not its
  purpose, so the purpose is read back from where it ran: free time and a
  round by their conversation's kind, a check-in by the firing just
  before it in the main chat; anything else in the main chat (a letter's
  wake, or a message of his) is a wake of the chat with a note saying so.

  Running again settles the failure as `retried` first, so a second
  click finds nothing, then runs the turn on the brain's turn
  supervisor: a turn takes minutes and the click answers at once. A
  credit refusal's entry runs every refused turn again, each purpose
  once.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Error
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Sunna

  @tasks :brain_turns

  @doc """
  What running a failed turn again would do, for the bell's button:
  `{:free_time, label}`, `{:round, label}`, `{:checkin, key, label}` or
  `{:chat, label}`.
  """
  @spec action(String.t(), map(), %{optional(String.t()) => String.t()}) :: tuple()
  def action(resident_id, failure, kinds) do
    case Map.get(kinds, failure.session_key) do
      "free_time" ->
        {:free_time, "Run free time now"}

      "round" ->
        {:round, "Run a round now"}

      _main_or_other ->
        case Sunna.checkin_fired_before(resident_id, failure.failed_at) do
          %{key: key, label: label} -> {:checkin, key, "Run the #{label || key} check-in now"}
          nil -> {:chat, "Wake her now"}
        end
    end
  end

  @doc "Runs one failed turn again: settled as retried, then started; `{:ok, label}`."
  @spec one(String.t(), String.t(), Actor.t()) :: {:ok, String.t()} | {:error, term()}
  def one(resident_id, turn_ref, %Actor{} = actor) do
    with {:ok, failure} <- open_failure(resident_id, turn_ref),
         {:ok, _settled} <- settle([failure], actor) do
      what = action(resident_id, failure, kinds(resident_id))
      start(resident_id, what, failure.reason, actor)
      {:ok, label(what)}
    end
  end

  @doc "Runs every turn the provider refused for credit again, each purpose once; `{:ok, labels}`."
  @spec credits(String.t(), Actor.t()) :: {:ok, [String.t()]} | {:error, term()}
  def credits(resident_id, %Actor{} = actor) do
    failures = Enum.filter(open_failures(resident_id), &credits?(&1.reason))

    with {:ok, _settled} <- settle(failures, actor) do
      kinds = kinds(resident_id)

      whats =
        failures
        |> Enum.map(&{action(resident_id, &1, kinds), &1.reason})
        |> Enum.uniq_by(fn {what, _reason} -> purpose(what) end)

      for {what, reason} <- whats, do: start(resident_id, what, reason, actor)
      {:ok, Enum.map(whats, fn {what, _} -> label(what) end)}
    end
  end

  defp purpose({:checkin, key, _label}), do: {:checkin, key}
  defp purpose({kind, _label}), do: kind

  defp label({:checkin, _key, label}), do: label
  defp label({_kind, label}), do: label

  defp start(resident_id, what, reason, actor) do
    Task.Supervisor.start_child(@tasks, fn -> run(resident_id, what, reason, actor) end)
  end

  defp run(resident_id, {:free_time, _}, _reason, actor),
    do: Sunna.retry_free_time(resident_id, actor)

  defp run(resident_id, {:round, _}, _reason, actor), do: Sunna.retry_round(resident_id, actor)

  defp run(resident_id, {:checkin, key, _}, _reason, actor),
    do: Sunna.retry_checkin(resident_id, key, actor)

  defp run(resident_id, {:chat, _}, reason, actor),
    do:
      Sunna.wake_main_now(
        resident_id,
        "A turn here failed earlier and your witness asked for it again (the failure: #{String.slice(reason || "unknown", 0, 200)}). Pick up where it left off.",
        actor
      )

  defp settle(failures, actor) do
    results =
      for f <- failures,
          do:
            Kumbukumbu.resolve_failure(
              f.resident_id,
              f.session_key,
              f.turn_ref,
              "retried",
              "run again from the bell",
              actor
            )

    case Enum.find(results, &(&1 != :ok)) do
      nil -> {:ok, length(failures)}
      failed -> failed
    end
  end

  defp open_failure(resident_id, turn_ref) do
    case Enum.find(open_failures(resident_id), &(&1.turn_ref == turn_ref)) do
      nil ->
        {:error,
         Error.new(:brain_no_such_failure, :brain_retry_failure_absent, turn_ref: turn_ref)}

      f ->
        {:ok, f}
    end
  end

  defp open_failures(resident_id),
    do:
      {:resident, resident_id}
      |> Kumbukumbu.failures()
      |> Enum.filter(&(&1.resident_id == resident_id))

  defp kinds(resident_id),
    do: Map.new(Kumbukumbu.sessions({:resident, resident_id}), &{&1.key, &1.kind})

  @doc "Whether a failure's reason is the provider refusing for credit: a 402 that says so."
  @spec credits?(String.t() | nil) :: boolean()
  def credits?(reason) when is_binary(reason),
    do: String.contains?(reason, "402") and String.contains?(String.downcase(reason), "credit")

  def credits?(_reason), do: false
end
