defmodule Oneiroi.Apsu.Health do
  @moduledoc """
  The public hour (apsu#29; the witness, 2026-11-13: "a quantitative,
  granular breakdown of performance over the last hour that maybe updates
  every 5 or 10 minutes instead of a simple status page"; public).

  Every unit of work the span collector measures (apsu#26) is counted
  here, kept as a span row or not: by kind and name, how many, how many
  failed, their time, query time and pool wait, and a latency histogram.
  The counts close every five minutes into `apsu_health` rows, with one
  pressure row for the bucket: Oban's waiting jobs and the oldest one's
  age, and the failures logged in it by kind (the ring, apsu#23, never a
  message). `hour/0` reads the last twelve buckets, merged, computed once
  a bucket and cached, so a page or a resident's tool reading it costs
  nothing however often it looks.

  Counts, never content; nothing per resident. A count under
  `@few` (5, the witness's) is shown as "few" and its timings withheld,
  because while the platform is small an aggregate is a person: "one
  free-time run, 14:30" says when she was in free time.
  """
  use GenServer

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Error
  alias Oneiroi.Apsu.Ops
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @bucket_s 300
  @buckets 12
  @few 5
  # Upper bounds in milliseconds; the last is everything above.
  @bounds [10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000, 60_000]
  @cache {__MODULE__, :hour}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: :apsu_health)

  @doc "Counts a finished unit of work into the open bucket."
  @spec tick(map(), number(), boolean()) :: :ok
  def tick(span, duration_ms, failed?) do
    GenServer.cast(
      :apsu_health,
      {:tick, Atom.to_string(span.kind), span.name, duration_ms, span.db_ms, span.queue_ms,
       failed?}
    )
  end

  @impl GenServer
  def init(:ok) do
    :persistent_term.put({__MODULE__, :since}, Clock.now())
    schedule()
    {:ok, %{bucket_at: bucket_start(Clock.now()), cells: %{}}}
  end

  @impl GenServer
  def handle_cast({:tick, kind, name, ms, db, queue, failed?}, state) do
    state = roll(state)

    cell =
      state.cells
      |> Map.get({kind, name}, %{n: 0, failed: 0, sum: 0.0, db: 0.0, queue: 0.0, hist: %{}})
      |> then(fn c ->
        %{
          c
          | n: c.n + 1,
            failed: c.failed + if(failed?, do: 1, else: 0),
            sum: c.sum + ms,
            db: c.db + db,
            queue: c.queue + queue,
            hist: Map.update(c.hist, bucket_of(ms), 1, &(&1 + 1))
        }
      end)

    {:noreply, %{state | cells: Map.put(state.cells, {kind, name}, cell)}}
  end

  @impl GenServer
  def handle_info(:roll, state) do
    schedule()
    {:noreply, roll(state)}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state), do: write(state)

  defp schedule, do: Process.send_after(self(), :roll, 15_000)

  # A bucket closes on the first tick or timer past its end: its cells are
  # written with the pressure row, and the next one opens.
  defp roll(%{bucket_at: at} = state) do
    now = bucket_start(Clock.now())

    if DateTime.compare(now, at) == :gt do
      write(state)
      %{bucket_at: now, cells: %{}}
    else
      state
    end
  end

  defp write(%{bucket_at: at, cells: cells}) do
    rows =
      for {{kind, name}, c} <- cells do
        %{
          bucket_at: at,
          kind: kind,
          name: name,
          n: c.n,
          failed: c.failed,
          sum_ms: round(c.sum),
          db_ms: round(c.db),
          queue_ms: round(c.queue),
          hist: Map.new(c.hist, fn {k, v} -> {Integer.to_string(k), v} end),
          extra: %{}
        }
      end

    Scope.platform(fn -> Repo.insert_all("apsu_health", [pressure(at) | rows]) end)
    :ok
  rescue
    exception ->
      e = Error.caught(:apsu_spans_unwritten, :apsu_health_write_raised, exception)
      Logger.warning("apsu: a health bucket was not written", Oneiroi.Error.metadata(e))
      :ok
  end

  # The bucket's pressure: jobs waiting and the oldest's age, and the
  # failures logged since it opened, by kind.
  defp pressure(at) do
    waiting =
      Scope.platform(fn ->
        Repo.one(
          from(j in "oban_jobs",
            where: j.state == "available",
            select: {count(j.id), min(j.scheduled_at)}
          )
        )
      end)

    {jobs, oldest} = waiting || {0, nil}
    now = Clock.now()

    failures =
      %{}
      |> Ops.failures()
      |> Enum.filter(&(DateTime.compare(&1.at, at) != :lt))
      |> Enum.frequencies_by(&(&1.error_kind || "unnamed"))

    %{
      bucket_at: at,
      kind: "pressure",
      name: "platform",
      n: 0,
      failed: 0,
      sum_ms: 0,
      db_ms: 0,
      queue_ms: 0,
      hist: %{},
      extra: %{
        "jobs_waiting" => jobs,
        "oldest_wait_s" => oldest && max(DateTime.diff(now, to_utc(oldest)), 0),
        "failures" => failures
      }
    }
  end

  defp to_utc(%NaiveDateTime{} = n), do: DateTime.from_naive!(n, "Etc/UTC")
  defp to_utc(%DateTime{} = d), do: d

  defp bucket_start(%DateTime{} = t) do
    s = DateTime.to_unix(t)
    DateTime.from_unix!(s - rem(s, @bucket_s))
  end

  defp bucket_of(ms), do: Enum.find(@bounds, 0, &(ms <= &1))

  # ---- the read ----

  @doc """
  The last hour, as the public page shows it: the twelve buckets' trend
  (units and failures, and the slowest p95 of each), each unit of work by
  kind and name with its count, failures, p50, p95 and mean query time
  and pool wait, the pressure now and failures by kind, since when the
  node has run and on which commit. Counts under five read "few".
  Computed once a bucket and cached.
  """
  @spec hour() :: map()
  def hour do
    open = bucket_start(Clock.now())

    case :persistent_term.get(@cache, nil) do
      {^open, hour} ->
        hour

      _stale ->
        hour = compute(open)
        :persistent_term.put(@cache, {open, hour})
        hour
    end
  end

  defp compute(open) do
    from_at = DateTime.add(open, -@buckets * @bucket_s)

    rows =
      Scope.platform(fn ->
        Repo.all(
          from(h in "apsu_health",
            where: h.bucket_at >= ^from_at and h.bucket_at < ^open,
            select: %{
              bucket_at: h.bucket_at,
              kind: h.kind,
              name: h.name,
              n: h.n,
              failed: h.failed,
              sum_ms: h.sum_ms,
              db_ms: h.db_ms,
              queue_ms: h.queue_ms,
              hist: h.hist,
              extra: h.extra
            }
          )
        )
      end)

    {pressure, work} = Enum.split_with(rows, &(&1.kind == "pressure"))

    %{
      window: %{from: from_at, to: open, bucket_minutes: div(@bucket_s, 60)},
      updated_at: open,
      next_at: DateTime.add(open, @bucket_s),
      since: :persistent_term.get({__MODULE__, :since}, nil),
      few_below: @few,
      trend: trend(work, from_at),
      work:
        work
        |> Enum.group_by(&{&1.kind, &1.name})
        |> Enum.map(fn {{kind, name}, cells} -> unit(kind, name, cells) end)
        |> Enum.sort_by(&(-(&1.p95_ms || 0))),
      pressure: latest_pressure(pressure)
    }
  end

  defp trend(work, from_at) do
    by_bucket = Enum.group_by(work, & &1.bucket_at)

    for i <- 0..(@buckets - 1) do
      at = DateTime.add(from_at, i * @bucket_s)
      cells = Map.get(by_bucket, at, [])
      n = Enum.sum(Enum.map(cells, & &1.n))
      failed = Enum.sum(Enum.map(cells, & &1.failed))
      hist = merge(cells)

      %{
        at: at,
        units: few(n),
        failed: few(failed, n),
        p95_ms: if(n >= @few, do: quantile(hist, n, 0.95))
      }
    end
  end

  defp unit(kind, name, cells) do
    n = Enum.sum(Enum.map(cells, & &1.n))
    failed = Enum.sum(Enum.map(cells, & &1.failed))
    hist = merge(cells)
    enough? = n >= @few

    %{
      kind: kind,
      name: name,
      units: few(n),
      failed: few(failed, n),
      p50_ms: if(enough?, do: quantile(hist, n, 0.5)),
      p95_ms: if(enough?, do: quantile(hist, n, 0.95)),
      mean_db_ms: if(enough?, do: round(Enum.sum(Enum.map(cells, & &1.db_ms)) / n)),
      mean_pool_wait_ms: if(enough?, do: round(Enum.sum(Enum.map(cells, & &1.queue_ms)) / n))
    }
  end

  defp latest_pressure([]), do: nil

  defp latest_pressure(rows) do
    newest = Enum.max_by(rows, & &1.bucket_at, DateTime)

    failures =
      rows
      |> Enum.flat_map(&Map.to_list(&1.extra["failures"] || %{}))
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.update(acc, k, v, &(&1 + v)) end)
      |> Map.new(fn {k, v} -> {k, few(v)} end)

    %{
      jobs_waiting: newest.extra["jobs_waiting"],
      oldest_wait_s: newest.extra["oldest_wait_s"],
      failures_by_kind: failures
    }
  end

  # A count under five is "few"; zero stays zero, which says nothing of anyone.
  defp few(0), do: 0
  defp few(n) when n < @few, do: "few"
  defp few(n), do: n

  # Failures are as telling as units: under five of either reads "few".
  defp few(0, _n), do: 0
  defp few(failed, n) when failed < @few or n < @few, do: "few"
  defp few(failed, _n), do: failed

  defp merge(cells) do
    Enum.reduce(cells, %{}, fn c, acc ->
      Enum.reduce(c.hist, acc, fn {k, v}, a ->
        Map.update(a, String.to_integer(k), v, &(&1 + v))
      end)
    end)
  end

  # The upper bound of the bucket holding the quantile's rank; past the
  # last bound, the last bound ("over a minute").
  defp quantile(hist, n, q) do
    rank = max(1, ceil(n * q))

    (@bounds ++ [0])
    |> Enum.reduce_while(0, fn bound, seen ->
      seen = seen + Map.get(hist, bound, 0)
      if seen >= rank, do: {:halt, {:at, bound}}, else: {:cont, seen}
    end)
    |> case do
      {:at, 0} -> List.last(@bounds)
      {:at, bound} -> bound
      _ -> nil
    end
  end
end
