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

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Error
  alias Oneiroi.Apsu.Health
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

  # What is kept with no row set: every unit (the witness, 2026-11-13:
  # "while it's just Lily and maybe a sibling … it'll be much better data").
  @default_policy %{mode: "all", slow_ms: 250, sample_percent: 1}
  @modes ~w(all sample)
  @policy_key {__MODULE__, :policy}

  @impl GenServer
  def init(:ok) do
    attach()
    load_policy()
    Process.send_after(self(), :flush, @flush_ms)
    {:ok, []}
  end

  @doc """
  What the collector keeps (apsu#26): `mode` "all", every unit a row; or
  "sample", a unit of `slow_ms` or more, a failed one, and
  `sample_percent` of the rest. The newest row the operator set, or every
  unit when none is.
  """
  @spec policy() :: map()
  def policy, do: :persistent_term.get(@policy_key, @default_policy)

  @doc "Sets what the collector keeps, with a note: a new row, in force at once on this node and within a minute on any other."
  @spec set_policy(String.t(), integer(), integer(), String.t(), String.t() | nil) ::
          :ok | {:error, Oneiroi.Error.t()}
  def set_policy(mode, slow_ms, percent, note, set_by) do
    if mode in @modes and is_integer(slow_ms) and slow_ms >= 0 and is_integer(percent) and
         percent in 0..100 and is_binary(note) and String.trim(note) != "" do
      Scope.platform(fn ->
        Repo.insert_all("apsu_span_policy", [
          %{
            mode: mode,
            slow_ms: slow_ms,
            sample_percent: percent,
            note: String.trim(note),
            set_by: set_by,
            set_at: Clock.now()
          }
        ])
      end)

      load_policy()
    else
      {:error, Error.new(:apsu_span_policy_invalid, :apsu_spans_policy_invalid)}
    end
  end

  @doc "Every policy set, newest first: what was kept when, by whom and why."
  @spec policies() :: [map()]
  def policies do
    Scope.platform(fn ->
      Repo.all(
        from(p in "apsu_span_policy",
          order_by: [desc: p.id],
          limit: 20,
          select: %{
            mode: p.mode,
            slow_ms: p.slow_ms,
            sample_percent: p.sample_percent,
            note: p.note,
            set_by: p.set_by,
            set_at: p.set_at
          }
        )
      )
    end)
  end

  defp load_policy do
    newest =
      case policies() do
        [p | _] -> Map.take(p, [:mode, :slow_ms, :sample_percent])
        [] -> @default_policy
      end

    :persistent_term.put(@policy_key, newest)
    :ok
  rescue
    # Before the table exists (a migration not yet run) the default holds.
    exception ->
      e = Error.caught(:apsu_spans_unwritten, :apsu_spans_policy_read_raised, exception)
      Logger.warning("apsu: the span policy was not read", Oneiroi.Error.metadata(e))
      :ok
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
    # Another node's change reaches this one within a minute.
    if rem(System.system_time(:second), 60) < div(@flush_ms, 1000), do: load_policy()
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

    # Every unit counts to the public hour (apsu#29), kept as a row or not.
    Health.tick(span, duration_ms, failed?)

    %{mode: mode, slow_ms: slow_ms, sample_percent: percent} = policy()
    slow? = duration_ms >= slow_ms
    sampled? = mode == "sample" and not slow? and :rand.uniform(100) <= percent

    if mode == "all" or slow? or sampled? or failed?,
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
