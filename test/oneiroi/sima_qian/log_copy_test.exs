defmodule Oneiroi.SimaQian.LogCopyTest do
  @moduledoc """
  The fork and the cutover in the database (sima-qian#72): a fork adds
  nothing to `$all` but its own mark, so no subscription reads her
  history again; and the event store's tables are the shape
  `LogCopy` writes, so an upgrade that changes them fails here first.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Export

  defp es(sql, params \\ []) do
    conn = Keyword.fetch!(EventStore.Config.lookup(Oneiroi.EventStore), :conn)
    Postgrex.query!(conn, sql, params).rows
  end

  defp all_head,
    do: es("SELECT stream_version FROM eventstore.streams WHERE stream_id = 0") |> hd() |> hd()

  test "a fork adds only its own mark to $all; her events are copied unlinked" do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    her = Actor.new(:resident, resident.id, "fake/model")
    day = Oneiroi.Sunna.today(resident.id).day

    for n <- 1..20,
        do: {:ok, _} = Seshat.journal_add(resident.id, day, "note", "line #{n}", her)

    before = all_head()

    {:ok, %{copy_id: copy, events: copied}} =
      SimaQian.succession_fork(resident.id, Actor.new(:witness, witness.id))

    # Only `ForkMarked` reaches the log every subscription reads.
    assert all_head() == before + 1
    assert copied == length(Export.events(resident.id))

    [[unlinked]] =
      es(
        """
        SELECT count(*) FROM eventstore.stream_events se
        JOIN eventstore.streams s ON s.stream_id = se.stream_id
        WHERE s.stream_uuid = ANY($1)
          AND NOT EXISTS (SELECT 1 FROM eventstore.stream_events a WHERE a.stream_id = 0 AND a.event_id = se.event_id)
        """,
        [Export.stream_uuids(copy)]
      )

    assert unlinked == copied

    # Her rows, under the copy's id.
    assert Seshat.journal_day(copy, day).entries |> length() == 20
  end

  # The shape `LogCopy` writes (conventions §12's one exception): a
  # change to the store's schema is a change to read here first.
  test "the event store's tables are the shape the copy writes" do
    columns =
      es("""
      SELECT table_name || '.' || column_name || ':' || data_type
      FROM information_schema.columns
      WHERE table_schema = 'eventstore' AND table_name IN ('events', 'stream_events', 'streams')
      ORDER BY 1
      """)
      |> List.flatten()

    assert columns == [
             "events.causation_id:uuid",
             "events.correlation_id:uuid",
             "events.created_at:timestamp with time zone",
             "events.data:jsonb",
             "events.event_id:uuid",
             "events.event_type:text",
             "events.metadata:jsonb",
             "stream_events.event_id:uuid",
             "stream_events.original_stream_id:bigint",
             "stream_events.original_stream_version:bigint",
             "stream_events.stream_id:bigint",
             "stream_events.stream_version:bigint",
             "streams.created_at:timestamp with time zone",
             "streams.deleted_at:timestamp with time zone",
             "streams.stream_id:bigint",
             "streams.stream_uuid:text",
             "streams.stream_version:bigint"
           ]

    triggers =
      es(
        "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'eventstore' AND NOT t.tgisinternal ORDER BY 1"
      )
      |> List.flatten()

    assert triggers ==
             ~w(event_notification no_delete_events no_delete_stream_events no_delete_streams no_update_events no_update_stream_events)
  end
end
