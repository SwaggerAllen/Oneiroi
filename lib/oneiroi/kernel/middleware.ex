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

  require Logger

  alias Commanded.Middleware.Pipeline
  import Pipeline

  @impl Commanded.Middleware
  def before_dispatch(%Pipeline{command: command} = pipeline) do
    case problems(command) do
      [] -> traced(pipeline)
      # The pipeline's response, not an error leaving a boundary: every
      # system's dispatch wraps it once with caught/4 at its own site.
      # oneiroi:allow error_site
      problems -> pipeline |> respond({:error, {:refused, problems}}) |> halt()
    end
  end

  # Every event carries the trace id of the request, job or turn that
  # dispatched it (apsu#27), the same one a span row and every log line
  # of that work carry: the join from a slow call to the events it caused.
  defp traced(pipeline) do
    case Keyword.get(Logger.metadata(), :trace_id) do
      nil -> pipeline
      trace -> assign_metadata(pipeline, "trace_id", to_string(trace))
    end
  end

  # The events a dispatch wrote, told to the span collector (apsu#27), so
  # a unit of work's row names the set of events it caused; the event
  # store is read through its API alone (conventions §12), so the join
  # is made as the events are written, not queried after.
  @impl Commanded.Middleware
  def after_dispatch(%Pipeline{assigns: assigns} = pipeline) do
    case Map.get(assigns, :events) do
      [_ | _] = events ->
        :telemetry.execute([:oneiroi, :apsu, :dispatch], %{count: length(events)}, %{
          events: Enum.map(events, &event_name/1)
        })

      _none ->
        :ok
    end

    pipeline
  end

  def after_dispatch(pipeline), do: pipeline

  defp event_name(%module{}), do: module |> Module.split() |> List.last()
  defp event_name(_event), do: "?"

  @impl Commanded.Middleware
  def after_failure(pipeline), do: pipeline

  @doc "Everything wrong with a command's attribution and its bounded names, all at once."
  @spec problems(struct()) :: [atom()]
  def problems(command) do
    actor = if Oneiroi.Actor.valid?(Map.get(command, :actor)), do: [], else: [:actor_required]
    at = if match?(%DateTime{}, Map.get(command, :at)), do: [], else: [:at_required]

    note =
      if decision?(command) and not note?(Map.get(command, :note)),
        do: [:note_required],
        else: []

    actor ++ at ++ note ++ overlong(command)
  end

  # The bounded names (`Oneiroi.Command`'s `bounds:`), checked as a
  # changeset over the command's values: one refusal per field too long.
  defp overlong(%module{} = command) do
    bounds =
      if Code.ensure_loaded?(module) and function_exported?(module, :__bounds__, 0),
        do: module.__bounds__(),
        else: []

    if bounds == [] do
      []
    else
      types = Map.new(bounds, fn {field, _max, _problem} -> {field, :string} end)
      values = Map.new(bounds, fn {field, _max, _problem} -> {field, Map.get(command, field)} end)

      changeset =
        Enum.reduce(bounds, Ecto.Changeset.cast({%{}, types}, values, Map.keys(types)), fn
          {field, max, _problem}, changeset ->
            Ecto.Changeset.validate_length(changeset, field, max: max)
        end)

      # Length errors alone: a value that is not text is the aggregate's
      # to refuse, and not a name too long.
      for {field, _max, problem} <- bounds, too_long?(changeset, field), do: problem
    end
  end

  defp overlong(_command), do: []

  defp too_long?(changeset, field) do
    Enum.any?(changeset.errors, fn {f, {_message, opts}} ->
      f == field and opts[:validation] == :length
    end)
  end

  # `function_exported?/3` is false for a module not loaded yet, so the
  # module is loaded first: before this, the first decision of a command
  # after a cold start passed without its note (CI on xenia's first run,
  # 2026-11-02, where the suite had not yet loaded `DecideMessage`).
  defp decision?(%module{}) do
    Code.ensure_loaded?(module) and function_exported?(module, :__decision__?, 0) and
      module.__decision__?()
  end

  defp decision?(_other), do: false

  defp note?(note) when is_binary(note), do: String.trim(note) != ""
  defp note?(_note), do: false
end
