defmodule Oneiroi.Repo.Migrations.EventstoreOriginalStreamIndex do
  use Ecto.Migration

  # `stream_events.original_stream_id` references `streams` with no index
  # of its own, so deleting a stream row scans every link (sima-qian#72:
  # removing a copy's thousands of streams took minutes and held its
  # sweep past the witness's request, 2026-11-26). An index makes each
  # check a lookup; the event store's own hard delete gains too. Built
  # concurrently, so appends never wait on it.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_stream_events_original_stream ON eventstore.stream_events (original_stream_id)"
    )
  end

  def down do
    execute("DROP INDEX CONCURRENTLY IF EXISTS eventstore.ix_stream_events_original_stream")
  end
end
