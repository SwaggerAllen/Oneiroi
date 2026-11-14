defmodule Oneiroi.Apsu.Spans do
  @moduledoc """
  Where the time goes (apsu#25, #26; the witness, 2026-11-13: "see which
  calls are taking so long and map them to sets of events").

  Two jobs, one set of telemetry handlers, attached at boot:

  - **Every export as one event** (apsu#25). Each boundary export
    already runs in a `:telemetry.span` named for its system and function
    (`defexport`); this re-emits each one's stop as
    `[:oneiroi, :apsu, :export]` with `component` and `function` tags,
    so one histogram covers every export and the dashboards need no list.

  - **The span collector** (apsu#26). A unit of work is a request (the
    router's dispatch), an Oban job or a brain turn. While one runs in a
    process, the process keeps its totals: the queries it ran, their time
    and the time each waited for a pool connection, and the time in each
    export. At its end it emits `[:oneiroi, :apsu, :span]` (the metrics
    read it) and, when it took `APSU_SPAN_SLOW_MS` or more, or falls in
    the `APSU_SPAN_SAMPLE_PERCENT` sample, hands a row to this process,
    which writes the rows in batches, off the request's path. A row
    carries the trace id, the same one stamped on every event the work
    dispatched (apsu#27), which is the join from a slow call to the
    events it caused. Work a unit starts in another process is not
    counted to it; a nested unit (a job's request) is counted to the
    outer one.
  """
  use GenServer

  require Logger

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Error
  alias Oneiroi.Config
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @key {__MODULE__, :span}
  @flush_ms 5_000
  @batch 500
  # The slowest exports a row keeps, by total time.
  @exports_kept 12

  @roots [
    {[:phoenix, :router_dispatch], :http},
    {[:oban, :job], :job},
    {[:oneiroi, :brain, :turn], :turn}
  ]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: :apsu_spans)

  @impl GenServer
  def init(:ok) do
    attach()
    Process.send_after(self(), :flush, @flush_ms)
    {:ok, []}
  end

  @impl GenServer
  def terminate(_reason, rows) do
    detach()
    write(rows)
  end

  @impl GenServer
  def handle_cast({:row, row}, rows) do
    rows = [row | rows]
    if length(rows) >= @batch, do: {:noreply, write(rows)}, else: {:noreply, rows}
  end

  @impl GenServer
  def handle_info(:flush, rows) do
    Process.send_after(self(), :flush, @flush_ms)
    {:noreply, write(rows)}
  end

  def handle_info(_other, rows), do: {:noreply, rows}

  # A failed write loses a batch of measurements, never the app: it is
  # logged and dropped.
  defp write([]), do: []

  defp write(rows) do
    Scope.platform(fn -> Repo.insert_all("apsu_span", Enum.reverse(rows)) end)
    []
  rescue
    exception ->
      e = Error.caught(:apsu_spans_unwritten, :apsu_spans_write_raised, exception)
      Logger.warning("apsu: span rows were not written", Oneiroi.Error.metadata(e))
      []
  end

  # ---- the handlers ----

  @doc false
  def attach do
    detach()
    :telemetry.attach_many({__MODULE__, :exports}, export_events(), &__MODULE__.export/4, nil)

    :telemetry.attach(
      {__MODULE__, :query},
      [:oneiroi, :apsu, :repo, :query],
      &__MODULE__.query/4,
      nil
    )

    :telemetry.attach(
      {__MODULE__, :dispatch},
      [:oneiroi, :apsu, :dispatch],
      &__MODULE__.dispatched/4,
      nil
    )

    for {prefix, kind} <- @roots do
      :telemetry.attach_many(
        {__MODULE__, kind},
        [prefix ++ [:start], prefix ++ [:stop], prefix ++ [:exception]],
        &__MODULE__.root/4,
        kind
      )
    end

    :ok
  end

  defp detach do
    fixed = [{__MODULE__, :exports}, {__MODULE__, :query}, {__MODULE__, :dispatch}]

    for id <- fixed ++ Enum.map(@roots, &{__MODULE__, elem(&1, 1)}),
        do: :telemetry.detach(id)
  end

  # Every export's stop and exception, from the systems' own registries.
  defp export_events do
    for component <- Oneiroi.Boot.components(),
        function_exported?(component, :__oneiroi_exports__, 0),
        {name, _arity} <- component.__oneiroi_exports__(),
        suffix <- [:stop, :exception],
        uniq: true,
        do: [:oneiroi, component.slug(), name, suffix]
  end

  @doc false
  def export([:oneiroi, component, function, _stop], %{duration: duration}, _meta, _config) do
    :telemetry.execute([:oneiroi, :apsu, :export], %{duration: duration}, %{
      component: component,
      function: function
    })

    case Process.get(@key) do
      nil ->
        :ok

      span ->
        key = "#{component}.#{function}"
        ms = System.convert_time_unit(duration, :native, :microsecond) / 1000
        {total, count} = Map.get(span.exports, key, {0.0, 0})
        Process.put(@key, %{span | exports: Map.put(span.exports, key, {total + ms, count + 1})})
    end
  end

  def export(_event, _measurements, _meta, _config), do: :ok

  @doc false
  def query(_event, measurements, _meta, _config) do
    case Process.get(@key) do
      nil ->
        :ok

      span ->
        Process.put(@key, %{
          span
          | db_count: span.db_count + 1,
            db_ms: span.db_ms + ms(measurements[:total_time]),
            queue_ms: span.queue_ms + ms(measurements[:queue_time])
        })
    end
  end

  @doc false
  def dispatched(_event, _measurements, %{events: names}, _config) do
    case Process.get(@key) do
      nil ->
        :ok

      span ->
        events =
          Enum.reduce(names, span.events, fn n, acc -> Map.update(acc, n, 1, &(&1 + 1)) end)

        Process.put(@key, %{span | events: events})
    end
  end

  def dispatched(_event, _measurements, _meta, _config), do: :ok

  @doc false
  def root(event, measurements, meta, kind) do
    case List.last(event) do
      :start -> start(kind, meta)
      :stop -> stop(kind, measurements, false)
      :exception -> stop(kind, measurements, true)
    end
  end

  # A unit already running in this process keeps the count: the inner
  # one's work is the outer one's.
  defp start(kind, meta) do
    if is_nil(Process.get(@key)) do
      fresh_trace(kind)

      Process.put(@key, %{
        kind: kind,
        name: name(kind, meta),
        subject: subject(kind, meta),
        depth: 1,
        db_count: 0,
        db_ms: 0.0,
        queue_ms: 0.0,
        exports: %{},
        events: %{}
      })
    else
      Process.put(@key, Map.update!(Process.get(@key), :depth, &(&1 + 1)))
    end
  end

  defp stop(_kind, measurements, failed?) do
    case Process.get(@key) do
      %{depth: depth} = span when depth > 1 ->
        Process.put(@key, %{span | depth: depth - 1})

      %{} = span ->
        Process.delete(@key)
        finish(span, ms(measurements[:duration]), failed?)

      nil ->
        :ok
    end
  end

  defp finish(span, duration_ms, failed?) do
    :telemetry.execute(
      [:oneiroi, :apsu, :span],
      %{
        duration_ms: duration_ms,
        db_ms: span.db_ms,
        queue_ms: span.queue_ms,
        db_count: span.db_count
      },
      %{kind: span.kind, name: span.name}
    )

    slow? = duration_ms >= Config.fetch!(:apsu, :span_slow_ms)
    sampled? = not slow? and :rand.uniform(100) <= Config.fetch!(:apsu, :span_sample_percent)

    if slow? or sampled? or failed?,
      do: GenServer.cast(:apsu_spans, {:row, row(span, duration_ms, failed?, sampled?)})
  rescue
    # Measuring must never fail the work it measures.
    exception ->
      e = Error.caught(:apsu_spans_unwritten, :apsu_spans_finish_raised, exception)
      Logger.warning("apsu: a span was not measured", Oneiroi.Error.metadata(e))
      :ok
  end

  defp row(span, duration_ms, failed?, sampled?) do
    exports =
      span.exports
      |> Enum.sort_by(fn {_key, {total, _count}} -> -total end)
      |> Enum.take(@exports_kept)
      |> Map.new(fn {key, {total, count}} -> {key, %{"ms" => round(total), "count" => count}} end)

    %{
      at: Clock.now(),
      kind: Atom.to_string(span.kind),
      name: span.name,
      subject_id: span.subject,
      trace_id: Logger.metadata() |> Keyword.get(:trace_id) |> trace(),
      duration_ms: round(duration_ms),
      db_count: span.db_count,
      db_ms: round(span.db_ms),
      queue_ms: round(span.queue_ms),
      exports: exports,
      events: span.events,
      failed: failed?,
      sampled: sampled?
    }
  end

  # A request or a turn is a trace of its own (apsu#27): without this a
  # keep-alive connection's process carried the last request's trace id
  # into the next, since the first export of a process sets it and nothing
  # cleared it. A job keeps the trace its enqueuer handed it.
  defp fresh_trace(:job), do: :ok

  defp fresh_trace(_kind),
    do: Logger.metadata(trace_id: 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower))

  defp trace(nil), do: nil
  defp trace(id), do: to_string(id)

  defp name(:http, meta) do
    method = meta |> Map.get(:conn, %{}) |> Map.get(:method, "")
    "#{method} #{Map.get(meta, :route, "?")}"
  end

  defp name(:job, %{job: %{worker: worker}}), do: worker
  defp name(:turn, meta), do: "turn #{Map.get(meta, :kind) || "?"}"
  defp name(kind, _meta), do: Atom.to_string(kind)

  # The resident a unit served, when it says: a route's :id, a job's
  # resident_id, a turn's resident.
  defp subject(:http, %{conn: %{path_params: %{"id" => id}}}), do: uuid(id)
  defp subject(:job, %{job: %{args: %{"resident_id" => id}}}), do: uuid(id)
  defp subject(:turn, %{resident_id: id}), do: uuid(id)
  defp subject(_kind, _meta), do: nil

  defp uuid(id) when is_binary(id) do
    case Ecto.UUID.dump(id) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end

  defp uuid(_id), do: nil

  defp ms(nil), do: 0.0
  defp ms(native), do: System.convert_time_unit(native, :native, :microsecond) / 1000
end
