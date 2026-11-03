defmodule Oneiroi.Projection do
  @moduledoc """
  What a system's Ecto projector adopts (conventions §6, §12):

      defmodule Oneiroi.AgathosDaimon.Projectors.Resident do
        use Oneiroi.Projection, name: "agathos_daimon_resident"

        fold %ResidentCreated{} = e, _metadata, fn multi ->
          Ecto.Multi.insert(multi, :row, %Row{...})
        end
      end

  A projector is a cross-tenant job by nature: it folds every resident's
  events into rows, so it runs under the platform scope, taken on the
  process at start and set on the connection inside every projection
  transaction by `fold/3`, which is the library's `project/3` with that
  one step prepended. That is the one place the platform scope is taken
  by machinery rather than by a named call; every other cross-tenant read
  is a `Oneiroi.Scope.platform/1` a reviewer can see.
  """

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)

    quote do
      # Atoms rather than aliases, for the reason `Oneiroi.Router` gives:
      # both are read when the projector runs, and a literal alias here
      # would put every projector on the compile-connected graph.
      use Commanded.Projections.Ecto,
        application: Module.concat([Oneiroi, Commanded]),
        repo: Module.concat([Oneiroi, Repo]),
        name: unquote(name),
        consistency: :strong

      import Oneiroi.Projection, only: [fold: 3]

      @impl Commanded.Event.Handler
      def init(config) do
        Oneiroi.Scope.put(:platform)
        {:ok, config}
      end

      # One event a projector cannot fold never stops the app (2026-11-03,
      # the outage this is the lesson of): see `Oneiroi.Projection.failed/4`.
      @impl Commanded.Event.Handler
      def error(error, event, context),
        do: Oneiroi.Projection.failed(unquote(name), error, event, context)
    end
  end

  require Logger

  alias Commanded.Event.FailureContext

  # A transient failure is retried this many times, waiting this long
  # times the attempt between them: bounds, guesses, not measured.
  @retries 3
  @backoff_ms 500

  # The database's own transient refusals, by Postgres code: what a retry
  # can cure. Anything else is the event or the code, and a retry would
  # meet it again.
  @transient ~w(serialization_failure deadlock_detected lock_not_available query_canceled
                admin_shutdown crash_shutdown cannot_connect_now too_many_connections)a

  @doc """
  What a projector does with an event it could not fold (2026-11-03): a
  transient failure (the connection, a deadlock, a serialization
  conflict) is retried #{@retries} times with backoff; anything else, and a
  transient one past its retries, is set aside: logged at error with the
  projector, the event's number, type and stream, and the reason, and
  told as `[:oneiroi, :projection, :parked]` telemetry, the hook an alert
  takes when there is alerting. The event itself is never lost: it stays
  in the store, and the projector can be replayed over it once the fold
  is fixed.

  Stopping instead, the library's default, restarted the projector onto
  the same event until the supervisor gave up and the app went down with
  it: one row too long for its column took every resident offline for an
  hour. One projection a row behind is a bug; the platform down is
  everybody's day.
  """
  @spec failed(String.t(), term(), struct() | nil, FailureContext.t()) ::
          :skip | {:retry, non_neg_integer(), FailureContext.t()}
  def failed(name, error, event, %FailureContext{} = failure) do
    reason = reason(error)
    context = failure.context || %{}
    attempts = Map.get(context, :attempts, 0) + 1

    if transient?(reason) and attempts <= @retries do
      {:retry, @backoff_ms * attempts,
       %{failure | context: Map.put(context, :attempts, attempts)}}
    else
      park(name, reason, event, failure.metadata || %{}, attempts)
      :skip
    end
  end

  defp reason({:error, reason}), do: reason
  defp reason({:error, reason, _stacktrace}), do: reason
  defp reason(other), do: other

  defp transient?(%Postgrex.Error{postgres: %{code: code}}), do: code in @transient

  # A lost connection is DBConnection's, which is not on this boundary's
  # list of dependencies; named at the call rather than referenced.
  defp transient?(%{__struct__: module}),
    do: module == Module.concat([DBConnection, ConnectionError])

  defp transient?(_reason), do: false

  # The event's identity and the failure's kind, never the event's data:
  # a transcript's words are not the log's to keep.
  defp park(name, reason, event, metadata, attempts) do
    facts = %{
      projector: name,
      event_type: event_type(event),
      event_number: Map.get(metadata, :event_number),
      stream_id: Map.get(metadata, :stream_id),
      attempts: attempts,
      reason: describe(reason)
    }

    Logger.error(
      "projection parked an event it could not fold: #{facts.projector} at event " <>
        "#{facts.event_number} (#{facts.event_type}, stream #{facts.stream_id}) after " <>
        "#{attempts} attempt(s): #{facts.reason}; the event is kept in the store, and the " <>
        "projection is one event behind until it is replayed",
      component: :projection,
      error_kind: :projection_parked,
      error_site: name,
      error_cause: facts.reason
    )

    :telemetry.execute([:oneiroi, :projection, :parked], %{count: 1}, facts)
  end

  defp event_type(%{__struct__: module}), do: inspect(module)
  defp event_type(_event), do: "unknown"

  # The kind of failure, without the values that caused it: a Postgres
  # error says its code and message, which name the column's limit and
  # not the row's words.
  defp describe(%Postgrex.Error{postgres: %{code: code, message: message}}),
    do: "postgres #{code}: #{message}"

  defp describe(%{__exception__: true} = exception), do: inspect(exception.__struct__)
  defp describe(reason) when is_atom(reason), do: inspect(reason)
  defp describe(%{__struct__: module}), do: inspect(module)
  defp describe(_reason), do: "an error term"

  @doc "The library's `project/3`, with the platform scope set on the connection first."
  defmacro fold(event, metadata, lambda) do
    quote do
      project(unquote(event), unquote(metadata), fn multi ->
        # The multi runs in the handler's process, so the process scope
        # is taken here as well as on the connection: `init/1` runs in a
        # different process than `handle/2` in the library's own startup.
        multi =
          Ecto.Multi.run(multi, :oneiroi_scope, fn repo, _changes ->
            Oneiroi.Scope.put(:platform)
            Oneiroi.Scope.set_on_connection(repo, :platform)
          end)

        unquote(lambda).(multi)
      end)
    end
  end
end
