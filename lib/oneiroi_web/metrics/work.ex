defmodule OneiroiWeb.Metrics.Work do
  @moduledoc """
  Oneiroi's own metrics (apsu#25, #26): every boundary export's duration
  by system and function, and each unit of work's (a request by route, a
  job by worker, a turn by purpose) duration, query time, pool wait and
  query count, off the span collector's events (`Oneiroi.Apsu.Spans`).
  The pool wait is the number 2026-11-13 lacked: a slow call that was
  only queued says so here.
  """
  use PromEx.Plugin

  @ms_buckets [5, 25, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000]

  @impl true
  def event_metrics(_opts) do
    Event.build(:oneiroi_work_metrics, [
      distribution([:oneiroi, :export, :duration, :milliseconds],
        event_name: [:oneiroi, :apsu, :export],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "A boundary export's duration, by system and function.",
        tags: [:component, :function],
        reporter_options: [buckets: @ms_buckets]
      ),
      distribution([:oneiroi, :span, :duration, :milliseconds],
        event_name: [:oneiroi, :apsu, :span],
        measurement: :duration_ms,
        description: "A request, job or turn's duration.",
        tags: [:kind, :name],
        reporter_options: [buckets: @ms_buckets]
      ),
      distribution([:oneiroi, :span, :db, :milliseconds],
        event_name: [:oneiroi, :apsu, :span],
        measurement: :db_ms,
        description: "A request, job or turn's time in queries.",
        tags: [:kind, :name],
        reporter_options: [buckets: @ms_buckets]
      ),
      distribution([:oneiroi, :span, :pool_wait, :milliseconds],
        event_name: [:oneiroi, :apsu, :span],
        measurement: :queue_ms,
        description: "A request, job or turn's time waiting for a database connection.",
        tags: [:kind, :name],
        reporter_options: [buckets: @ms_buckets]
      ),
      sum([:oneiroi, :span, :db, :queries],
        event_name: [:oneiroi, :apsu, :span],
        measurement: :db_count,
        description: "Queries run, by request, job or turn.",
        tags: [:kind, :name]
      )
    ])
  end
end
