defmodule Oneiroi.Event.Codec do
  @moduledoc """
  The runtime half of `Oneiroi.Event`: what restores a decoded event's
  typed fields, and what tells an event module from any other. Kept out
  of the macro module so that a change here recompiles nothing that
  merely declares an event.
  """

  @doc """
  Restores the typed fields a JSON round trip flattens: the actor struct
  and the instant fields (`at` and the event's `instants:`). Every event's
  decoder delegates here so the rule has one implementation.
  """
  @spec restore(struct(), [atom()]) :: struct()
  def restore(%{actor: actor} = event, instants \\ [:at]) do
    Enum.reduce(instants, %{event | actor: Oneiroi.Actor.from_map(actor)}, fn field, event ->
      Map.update!(event, field, &instant/1)
    end)
  end

  # Microsecond precision whatever the wire carried: the projections'
  # columns are `:utc_datetime_usec`, and an instant written without a
  # fraction reads back coarser than it was stored.
  defp instant(%DateTime{microsecond: {us, _}} = at), do: %{at | microsecond: {us, 6}}

  defp instant(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, parsed, _offset} -> instant(parsed)
      _error -> at
    end
  end

  defp instant(at), do: at

  @doc "Whether a module is an event built with this macro."
  @spec event_module?(module()) :: boolean()
  def event_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__version__, 0)
  end
end
