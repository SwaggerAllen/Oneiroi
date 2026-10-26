defmodule Oneiroi.Commanded.Middleware.Actor do
  @moduledoc """
  The event validator at the command edge (conventions §6, spec §3.1): a
  command without a well-formed `Oneiroi.Actor` is refused, and a decision
  command without a non-empty `note` is refused, before any aggregate sees
  it. Refused, not warned: an event without its actor is a line in the
  log nobody can attribute, forever.

  Every system's router installs this middleware; a test
  (`Oneiroi.RoutersTest`) asserts it.
  """
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Pipeline

  @impl Commanded.Middleware
  def before_dispatch(%Pipeline{command: command} = pipeline) do
    case problems(command) do
      [] -> pipeline
      problems -> pipeline |> respond({:error, {:refused, problems}}) |> halt()
    end
  end

  @impl Commanded.Middleware
  def after_dispatch(pipeline), do: pipeline

  @impl Commanded.Middleware
  def after_failure(pipeline), do: pipeline

  @doc "Everything wrong with a command's attribution, all at once."
  @spec problems(struct()) :: [atom()]
  def problems(command) do
    actor = if Oneiroi.Actor.valid?(Map.get(command, :actor)), do: [], else: [:actor_required]
    at = if match?(%DateTime{}, Map.get(command, :at)), do: [], else: [:at_required]

    note =
      if decision?(command) and not note?(Map.get(command, :note)),
        do: [:note_required],
        else: []

    actor ++ at ++ note
  end

  defp decision?(%module{}) do
    function_exported?(module, :__decision__?, 0) and module.__decision__?()
  end

  defp decision?(_other), do: false

  defp note?(note) when is_binary(note), do: String.trim(note) != ""
  defp note?(_note), do: false
end
