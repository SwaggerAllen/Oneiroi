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
  alias Oneiroi.SimaQian.LogCopy

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

  # 2026-11-26: a fork's rows carried her session keys under the
  # witness's account, and his view of her transcript found two.
  test "a fork's rows stay out of the witness's view; a sweep removes an orphaned copy" do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    andrew = Actor.new(:witness, witness.id)
    {:ok, chat} = Oneiroi.Kumbukumbu.main_session(resident.id, witness.id, andrew)

    {:ok, %{copy_id: kept}} = SimaQian.succession_fork(resident.id, andrew)

    assert {:ok, _session, _messages} =
             Oneiroi.Kumbukumbu.transcript({:account, witness.id}, chat)

    # An orphan: a copy's events and rows with nothing recording it.
    orphan = Ecto.UUID.generate()

    {:ok, _} =
      LogCopy.events(resident.id, orphan, %{
        "fork_of" => resident.id,
        "imported" => true
      })

    assert {:ok, [^orphan]} = SimaQian.succession_sweep(resident.id, [kept])
    assert Export.stream_uuids(orphan) == []
    assert Export.stream_uuids(kept) != []
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

    # Deleting a stream row checks its links by this index (2026-11-26).
    assert [[_]] =
             es(
               "SELECT 1 FROM pg_indexes WHERE schemaname = 'eventstore' AND indexname = 'ix_stream_events_original_stream'"
             )

    assert triggers ==
             ~w(event_notification no_delete_events no_delete_stream_events no_delete_streams no_update_events no_update_stream_events)
  end
end
