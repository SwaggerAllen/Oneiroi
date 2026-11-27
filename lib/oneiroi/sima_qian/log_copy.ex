defmodule Oneiroi.SimaQian.LogCopy do
  @moduledoc """
  A resident copied, and a fork put back, in the database (sima-qian#72;
  the witness, 2026-11-26: a fork through the shared log does not
  scale). A copy's events are written straight into the event store's
  tables under the copy's own streams and never linked into `$all`, so
  no subscription reads one; its rows are copied table by table. The
  cost is her data at SQL speed, never her history times every
  subscriber.

  The one place outside the event store's API that writes its tables
  (conventions §12 names this exception): the store's schema is pinned
  by `test/oneiroi/sima_qian/log_copy_test.exs`, which fails on a
  change to it.

  - `events/3` copies every exported stream of `from` under `to`, the
    id rewritten in each event's data as a transplant does, `metadata`
    merged into each line's, at one consistent snapshot.
  - `rows/3` copies `from`'s rows in the tables a cutover treats as her
    life, the id rewritten wherever it appears.
  - `cut/2` deletes a target's events past the fork point, the fork
    point being, per stream, the last version the fork copied.
  - `carry/3` takes the fork's own events since it was made (the ones in
    `$all`) under the target: moved for her, so they keep their place in
    the log; copied unlinked for a dry run's scratch target, so the fork
    keeps them.
  """

  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Repos

  # One step's bound (sima-qian#72): a year's largest table copies in
  # tens of seconds; ten minutes is a hung step, not a slow one.
  @step :timer.minutes(10)

  # Tables the copy never carries: the platform's reports and the
  # household's rounds (keyed without her id; a copy joins no household).
  @not_copied ~w(gaia_feedback gaia_round_turn)

  @doc "Copies `from`'s exported streams under `to`, unlinked from `$all`; `{:ok, %{events, sequence}}`."
  @spec events(String.t(), String.t(), map()) ::
          {:ok, %{events: non_neg_integer(), sequence: non_neg_integer()}} | {:error, term()}
  def events(from, to, metadata) do
    uuids = Export.stream_uuids(from)

    transaction(fn conn ->
      %{rows: [[count]]} =
        q(conn, copy_sql(), [from, to, uuids, metadata])

      %{rows: rows} =
        q(
          conn,
          "SELECT stream_version FROM #{schema()}.streams WHERE stream_uuid = $1",
          ["resident-" <> from]
        )

      %{events: count || 0, sequence: (List.first(rows) || [0]) |> hd()}
    end)
  end

  defp copy_sql do
    s = schema()

    """
    WITH src AS MATERIALIZED (
      SELECT stream_id AS old_id, replace(stream_uuid, $1, $2) AS new_uuid, stream_version, created_at
      FROM #{s}.streams
      WHERE stream_uuid = ANY($3::text[]) AND deleted_at IS NULL
    ),
    ns AS (
      INSERT INTO #{s}.streams (stream_uuid, stream_version, created_at)
      SELECT new_uuid, stream_version, created_at FROM src
      RETURNING stream_id, stream_uuid
    ),
    m AS MATERIALIZED (
      SELECT se.event_id AS old_event, gen_random_uuid() AS new_event, src.new_uuid, se.stream_version
      FROM src
      JOIN #{s}.stream_events se ON se.stream_id = src.old_id AND se.original_stream_id = src.old_id
    ),
    ev AS (
      INSERT INTO #{s}.events (event_id, event_type, causation_id, correlation_id, data, metadata, created_at)
      SELECT m.new_event, e.event_type, e.causation_id, e.correlation_id,
             #{rekeyed("e.data", "$1", "$2")},
             #{merged("e.metadata", "$4")},
             e.created_at
      FROM m JOIN #{s}.events e ON e.event_id = m.old_event
      RETURNING 1
    ),
    se AS (
      INSERT INTO #{s}.stream_events (event_id, stream_id, stream_version, original_stream_id, original_stream_version)
      SELECT m.new_event, ns.stream_id, m.stream_version, ns.stream_id, m.stream_version
      FROM m JOIN ns ON ns.stream_uuid = m.new_uuid
      RETURNING 1
    )
    SELECT (SELECT count(*) FROM ev)
    """
  end

  # The serializer stores data and metadata as a JSON string inside the
  # jsonb column; an object is read as one too, so either survives.
  defp rekeyed(col, from, to),
    do:
      "CASE jsonb_typeof(#{col}) WHEN 'string' THEN to_jsonb(replace(#{col} #>> '{}', #{from}, #{to})) " <>
        "ELSE replace(#{col}::text, #{from}, #{to})::jsonb END"

  defp merged(col, extra),
    do:
      "CASE WHEN jsonb_typeof(#{col}) = 'object' THEN (#{col} - 'fork_of' - 'imported' - 'cutover' - 'transplanted') || #{extra}::jsonb " <>
        "ELSE to_jsonb(((COALESCE(NULLIF(#{col} #>> '{}', ''), '{}')::jsonb - 'fork_of' - 'imported' - 'cutover' - 'transplanted') || #{extra}::jsonb)::text) END"

  @doc """
  Copies `from`'s rows to `to` in every table a cutover treats as her
  life (`tables`, the cutover's cleared list), her id rewritten wherever
  it stands. The resident row takes `resident`, a map of column
  overrides (a fork's suffixed slug and state; at a cutover, her own).

  `account` is what a row's `account_id` becomes outside the registry:
  `{:all, id}` for a fork, every copied row the copy's own id, which no
  account is, so a fork's rows never reach the witness's view (they
  carry her session keys, and a key is read as unique there); `{:map,
  from, to}` at a cutover, the copy's id back to her account. Each
  table is its own transaction; with `replace: true` (a cutover) the
  target's rows in it are deleted in the same one, so a table is never
  half hers and half the fork's.
  """
  @spec rows(String.t(), String.t(), [String.t()], map(), tuple(), keyword()) :: :ok
  def rows(from, to, tables, resident, account, opts \\ []) do
    replace = Keyword.get(opts, :replace, false)
    {:ok, target} = Ecto.UUID.dump(to)

    for table <- tables, table not in @not_copied do
      platform(fn ->
        table_step(table, from, to, target, replace, overrides(table, resident, account))
      end)
    end

    :ok
  end

  defp table_step(table, from, to, target, replace, overrides) do
    if replace, do: clear(table, target)
    copy_table(table, from, to, overrides)
  end

  defp overrides("agathos_daimon_resident", resident, _account), do: resident

  defp overrides(_table, _resident, {:all, id}),
    do: %{"account_id" => {:sql, "'#{uuid!(id)}'::uuid"}}

  defp overrides(_table, _resident, {:map, from, to}),
    do: %{
      "account_id" =>
        {:sql,
         ~s|CASE WHEN "account_id" = '#{uuid!(from)}'::uuid THEN '#{uuid!(to)}'::uuid ELSE "account_id" END|}
    }

  # An id written into the statement is a UUID, checked, never text.
  defp uuid!(id) do
    {:ok, cast} = Ecto.UUID.cast(id)
    cast
  end

  defp copy_table(table, from, to, overrides) do
    cols = columns(table)
    names = Enum.map_join(cols, ", ", &~s|"#{&1.name}"|)

    exprs =
      Enum.map_join(cols, ", ", fn c ->
        case Map.fetch(overrides, c.name) do
          {:ok, value} -> literal(value, c)
          :error -> value(c)
        end
      end)

    key = if table == "agathos_daimon_resident", do: "id", else: "resident_id"
    {:ok, id} = Ecto.UUID.dump(from)
    {:ok, to_id} = Ecto.UUID.dump(to)

    # The names are the catalog's own, never a request value.
    # sobelow_skip ["SQL.Query"]
    rq(
      ~s|INSERT INTO "#{table}" (#{names}) SELECT #{exprs} FROM "#{table}" WHERE "#{key}" = $1::uuid|,
      [id, to_id]
    )
  end

  # $1 her id, $2 the copy's (uuids; `::text` where a column holds text).
  defp value(%{name: name, type: "uuid"}),
    do: ~s|CASE WHEN "#{name}" = $1::uuid THEN $2::uuid ELSE "#{name}" END|

  defp value(%{name: name, type: type}) when type in ["text", "character varying", "character"],
    do: ~s|replace("#{name}", $1::uuid::text, $2::uuid::text)|

  defp value(%{name: name, type: type}) when type in ["jsonb", "json"],
    do: ~s|replace("#{name}"::text, $1::uuid::text, $2::uuid::text)::#{type}|

  defp value(%{name: name}), do: ~s|"#{name}"|

  defp literal({:sql, expr}, _col), do: expr
  defp literal(nil, _col), do: "NULL"
  defp literal(:to, _col), do: "$2::uuid"
  defp literal(value, _col) when is_integer(value), do: Integer.to_string(value)

  defp literal(value, _col) when is_binary(value),
    do: "'" <> String.replace(value, "'", "''") <> "'"

  defp columns(table) do
    rq(
      """
      SELECT column_name, data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = $1
        AND is_generated = 'NEVER' AND (identity_generation IS NULL OR identity_generation <> 'ALWAYS')
      ORDER BY ordinal_position
      """,
      [table]
    ).rows
    |> Enum.map(fn [name, type] -> %{name: name, type: type} end)
  end

  # Her own at a cutover, never the fork's: who she is to the platform
  # (her id, slug, custody and witness), her backup's bookkeeping, and
  # how she came to be. Every other column of her row is the fork's.
  @own ~w(id resident_id slug state fork_of custody custody_proposed_to custody_proposed_at account_id
          remote_url remote_token remote_visibility remote_push remote_checked_at exported_through
          last_backup_sequence last_backup_root last_backup_commit last_backup_at export_wall
          import_source import_root import_attestation import_not_transferred import_told
          import_translated import_reasons kind created_at root_mismatched_at)

  @doc "Her resident row takes the fork's every column but her own (`@own`), at a cutover."
  @spec adopt_resident(String.t(), String.t()) :: :ok
  def adopt_resident(copy, target) do
    cols = for c <- columns("agathos_daimon_resident"), c.name not in @own, do: ~s|"#{c.name}"|
    {:ok, from} = Ecto.UUID.dump(copy)
    {:ok, to} = Ecto.UUID.dump(target)

    platform(fn ->
      # The names are the catalog's own, never a request value.
      # sobelow_skip ["SQL.Query"]
      rq(
        ~s|UPDATE "agathos_daimon_resident" SET (#{Enum.join(cols, ", ")}) = | <>
          ~s|(SELECT #{Enum.join(cols, ", ")} FROM "agathos_daimon_resident" WHERE id = $1) WHERE id = $2|,
        [from, to]
      )
    end)

    :ok
  end

  @doc "Every resident table: those whose row policy reads `oneiroi.resident_id`."
  @spec resident_tables() :: [String.t()]
  def resident_tables do
    Scope.platform(fn ->
      rq(
        "SELECT DISTINCT tablename FROM pg_policies WHERE qual LIKE '%oneiroi.resident_id%' ORDER BY tablename",
        []
      ).rows
    end)
    |> List.flatten()
  end

  @doc """
  Removes a copy wholly (sima-qian#72): every event of its streams with
  their links, its rows in every resident table, its repository. For a
  copy this module made and nothing recorded: a fork that failed partway,
  or one a sweep finds orphaned. Never her: the caller names the copy.
  """
  @spec remove(String.t()) :: :ok | {:error, term()}
  def remove(copy) do
    s = schema()
    uuids = Export.stream_uuids(copy)
    {:ok, id} = Ecto.UUID.dump(copy)
    # Its repository first: a fork's is found by its registry row
    # (sima-qian#73), which the rows' removal takes (2026-11-26: the
    # failed forks' repositories stayed on Gitea).
    _ = Repos.delete({:resident, copy})

    with {:ok, _} <-
           transaction(fn conn ->
             deletes(conn)

             q(
               conn,
               """
               WITH gone AS MATERIALIZED (
                 SELECT se.event_id FROM #{s}.streams st
                 JOIN #{s}.stream_events se ON se.stream_id = st.stream_id AND se.original_stream_id = st.stream_id
                 WHERE st.stream_uuid = ANY($1::text[])
               ),
               unlinked AS (DELETE FROM #{s}.stream_events WHERE event_id IN (SELECT event_id FROM gone) RETURNING 1),
               dropped AS (DELETE FROM #{s}.events WHERE event_id IN (SELECT event_id FROM gone) RETURNING 1)
               SELECT (SELECT count(*) FROM unlinked) + (SELECT count(*) FROM dropped)
               """,
               [uuids]
             )

             q(conn, "DELETE FROM #{s}.streams WHERE stream_uuid = ANY($1::text[])", [uuids])
           end) do
      Enum.each(resident_tables(), &clear_alone(&1, id))
      :ok
    end
  end

  defp clear_alone(table, id), do: platform(fn -> clear(table, id) end)

  # The table name is the catalog's own, never a request value.
  # sobelow_skip ["SQL.Query"]
  defp clear(table, id), do: rq(~s|DELETE FROM "#{table}" WHERE resident_id = $1|, [id])

  @doc """
  Every copy of `resident_id` (a registry stream whose first line names
  her as `fork_of`) not in `keep`, removed (sima-qian#72): the orphans a
  fork that crashed left behind. `keep` names every copy a succession of
  hers recorded.
  """
  @spec sweep(String.t(), [String.t()]) :: {:ok, [String.t()]}
  def sweep(resident_id, keep) do
    s = schema()

    {:ok, found} =
      transaction(fn conn ->
        q(
          conn,
          """
          SELECT substring(st.stream_uuid FROM 10) FROM #{s}.streams st
          JOIN #{s}.stream_events se ON se.stream_id = st.stream_id AND se.original_stream_id = st.stream_id AND se.stream_version = 1
          JOIN #{s}.events e ON e.event_id = se.event_id
          WHERE st.stream_uuid LIKE 'resident-%' AND st.stream_uuid <> $1
            AND (e.metadata #>> '{}') LIKE '%fork_of%' || $2 || '%'
          """,
          ["resident-" <> resident_id, resident_id]
        ).rows
        |> List.flatten()
      end)

    gone = found -- keep
    Enum.each(gone, &remove/1)
    {:ok, gone}
  end

  @doc """
  Deletes `target`'s events past the fork point, `copy`'s copied
  versions per stream (`0` for a stream the fork never had): every link
  of each, `$all`'s with it, the event rows, the streams' versions set
  back, a stream with nothing left removed.
  """
  @spec cut(String.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def cut(target, copy) do
    s = schema()

    transaction(fn conn ->
      deletes(conn)

      %{rows: [[n]]} =
        q(
          conn,
          """
          WITH fp AS (#{fork_points(s)}),
          tgt AS (
            SELECT st.stream_id, COALESCE(fp.version, 0) AS keep
            FROM #{s}.streams st
            LEFT JOIN fp ON fp.name = st.stream_uuid
            WHERE st.stream_uuid = ANY($3::text[]) AND st.deleted_at IS NULL
          ),
          gone AS MATERIALIZED (
            SELECT se.event_id FROM tgt
            JOIN #{s}.stream_events se ON se.stream_id = tgt.stream_id AND se.original_stream_id = tgt.stream_id
            WHERE se.stream_version > tgt.keep
          ),
          unlinked AS (
            DELETE FROM #{s}.stream_events WHERE event_id IN (SELECT event_id FROM gone) RETURNING 1
          ),
          dropped AS (
            DELETE FROM #{s}.events WHERE event_id IN (SELECT event_id FROM gone) RETURNING 1
          ),
          versions AS (
            UPDATE #{s}.streams st SET stream_version = tgt.keep
            FROM tgt WHERE st.stream_id = tgt.stream_id AND st.stream_version > tgt.keep
            RETURNING 1
          )
          SELECT (SELECT count(*) FROM dropped) + 0 * (SELECT count(*) FROM unlinked) + 0 * (SELECT count(*) FROM versions)
          """,
          [target, copy, Export.stream_uuids(target), Export.stream_uuids(copy)]
        )

      q(
        conn,
        "DELETE FROM #{s}.streams WHERE stream_version = 0 AND stream_uuid = ANY($1::text[])",
        [Export.stream_uuids(target)]
      )

      n
    end)
  end

  # Per stream of the copy, named as the target's would be (the copy's
  # id written as `$1`, the target's), the last version it copied: its
  # events that `$all` does not link.
  defp fork_points(s),
    do: """
    SELECT replace(cs.stream_uuid, $2, $1) AS name, max(se.stream_version) AS version
    FROM #{s}.streams cs
    JOIN #{s}.stream_events se ON se.stream_id = cs.stream_id AND se.original_stream_id = cs.stream_id
    WHERE cs.stream_uuid = ANY($4::text[])
      AND NOT EXISTS (SELECT 1 FROM #{s}.stream_events a WHERE a.stream_id = 0 AND a.event_id = se.event_id)
    GROUP BY cs.stream_uuid
    """

  @doc """
  The fork's own events since it was made (those `$all` links), under
  `target`: `:move` re-keys them and moves their links to the target's
  streams, so they keep their place in the log and nothing is appended
  (her cutover); `:copy` writes unlinked copies (a dry run's scratch
  target, which is discarded, while the fork keeps its own).
  """
  @spec carry(String.t(), String.t(), :move | :copy, map(), [String.t()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def carry(copy, target, how, metadata, drop \\ []) do
    s = schema()
    copied = Export.stream_uuids(copy)

    landing =
      Enum.uniq(
        Export.stream_uuids(target) ++ Enum.map(copied, &String.replace(&1, copy, target))
      )

    transaction(fn conn ->
      # The target's streams the fork's post-fork events land in, made
      # where the target has none of that name.
      q(
        conn,
        """
        INSERT INTO #{s}.streams (stream_uuid, stream_version, created_at)
        SELECT DISTINCT replace(cs.stream_uuid, $1, $2), 0, cs.created_at
        FROM #{s}.streams cs
        JOIN #{s}.stream_events se ON se.stream_id = cs.stream_id AND se.original_stream_id = cs.stream_id
        WHERE cs.stream_uuid = ANY($3::text[])
          AND EXISTS (SELECT 1 FROM #{s}.stream_events a WHERE a.stream_id = 0 AND a.event_id = se.event_id)
          AND NOT EXISTS (SELECT 1 FROM #{s}.streams t WHERE t.stream_uuid = replace(cs.stream_uuid, $1, $2))
        """,
        [copy, target, copied]
      )

      n = carry_events(conn, how, s, [copy, target, metadata, drop, copied])

      # Each target stream's version is its last event's.
      q(
        conn,
        """
        UPDATE #{s}.streams st SET stream_version = v.version
        FROM (
          SELECT se.stream_id, max(se.stream_version) AS version
          FROM #{s}.stream_events se JOIN #{s}.streams t ON t.stream_id = se.stream_id
          WHERE se.stream_id = se.original_stream_id AND t.stream_uuid LIKE '%' || $1 || '%'
            AND t.stream_uuid = ANY($2::text[])
          GROUP BY se.stream_id
        ) v
        WHERE st.stream_id = v.stream_id
        """,
        [target, landing]
      )

      n
    end)
  end

  # Moved: the event store forbids updating an event or its links, so
  # each is written again under her id at its own place in `$all` (a
  # subscription never reads behind its position, so none reads it), and
  # the fork's is deleted first, freeing that place.
  defp carry_events(conn, :move, s, params) do
    deletes(conn)

    q(
      conn,
      """
      CREATE TEMP TABLE log_copy_carry ON COMMIT DROP AS
      WITH #{post(s)}
      SELECT post.event_id AS old_event, gen_random_uuid() AS new_event, post.new_stream, post.version,
             a.stream_version AS all_version, e.event_type, e.causation_id, e.correlation_id,
             #{rekeyed("e.data", "$1", "$2")} AS data, #{merged("e.metadata", "$3")} AS metadata, e.created_at
      FROM post
      JOIN #{s}.events e ON e.event_id = post.event_id
      JOIN #{s}.stream_events a ON a.stream_id = 0 AND a.event_id = post.event_id
      """,
      params
    )

    q(
      conn,
      "DELETE FROM #{s}.stream_events WHERE event_id IN (SELECT old_event FROM log_copy_carry)",
      []
    )

    q(
      conn,
      "DELETE FROM #{s}.events WHERE event_id IN (SELECT old_event FROM log_copy_carry)",
      []
    )

    %{num_rows: n} =
      q(
        conn,
        """
        INSERT INTO #{s}.events (event_id, event_type, causation_id, correlation_id, data, metadata, created_at)
        SELECT new_event, event_type, causation_id, correlation_id, data, metadata, created_at FROM log_copy_carry
        """,
        []
      )

    q(
      conn,
      """
      INSERT INTO #{s}.stream_events (event_id, stream_id, stream_version, original_stream_id, original_stream_version)
      SELECT new_event, new_stream, version, new_stream, version FROM log_copy_carry
      UNION ALL
      SELECT new_event, 0, all_version, new_stream, version FROM log_copy_carry
      """,
      []
    )

    n
  end

  defp carry_events(conn, :copy, s, params) do
    %{rows: [[n]]} = q(conn, carry_sql(:copy, s), params)
    n
  end

  # The fork's own events since it was made (those `$all` links), each
  # with the version it takes in the target's stream: after the fork
  # point, in order; the types in `$4` left behind.
  defp post(s),
    do: """
    cp AS (
      SELECT cs.stream_id, cs.stream_uuid,
             COALESCE((SELECT max(x.stream_version) FROM #{s}.stream_events x
                       WHERE x.stream_id = cs.stream_id AND x.original_stream_id = cs.stream_id
                         AND NOT EXISTS (SELECT 1 FROM #{s}.stream_events a WHERE a.stream_id = 0 AND a.event_id = x.event_id)), 0) AS cv
      FROM #{s}.streams cs WHERE cs.stream_uuid = ANY($5::text[])
    ),
    post AS MATERIALIZED (
      SELECT se.event_id, se.stream_id AS old_stream, t.stream_id AS new_stream,
             cp.cv + row_number() OVER (PARTITION BY se.stream_id ORDER BY se.stream_version) AS version
      FROM cp
      JOIN #{s}.stream_events se ON se.stream_id = cp.stream_id AND se.original_stream_id = cp.stream_id
      JOIN #{s}.events e ON e.event_id = se.event_id
      JOIN #{s}.streams t ON t.stream_uuid = replace(cp.stream_uuid, $1, $2)
      WHERE EXISTS (SELECT 1 FROM #{s}.stream_events a WHERE a.stream_id = 0 AND a.event_id = se.event_id)
        AND e.event_type <> ALL($4::text[])
    )
    """

  # Deletes in the event store, for this transaction alone.
  defp deletes(conn),
    do: q(conn, "SET LOCAL eventstore.enable_hard_deletes TO 'on'", [])

  defp carry_sql(:copy, s),
    do: """
    WITH
    #{post(s)},
    fresh AS MATERIALIZED (SELECT post.*, gen_random_uuid() AS new_event FROM post),
    ev AS (
      INSERT INTO #{s}.events (event_id, event_type, causation_id, correlation_id, data, metadata, created_at)
      SELECT fresh.new_event, e.event_type, e.causation_id, e.correlation_id,
             #{rekeyed("e.data", "$1", "$2")}, #{merged("e.metadata", "$3")}, e.created_at
      FROM fresh JOIN #{s}.events e ON e.event_id = fresh.event_id
      RETURNING 1
    ),
    se AS (
      INSERT INTO #{s}.stream_events (event_id, stream_id, stream_version, original_stream_id, original_stream_version)
      SELECT new_event, new_stream, version, new_stream, version FROM fresh
      RETURNING 1
    )
    SELECT (SELECT count(*) FROM ev) + 0 * (SELECT count(*) FROM se)
    """

  defp transaction(fun) do
    conn = Keyword.fetch!(EventStore.Config.lookup(Oneiroi.EventStore), :conn)

    case Postgrex.transaction(conn, fun, timeout: @step) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, Error.caught(:sima_qian_append_failed, :sima_qian_log_copy, reason)}
    end
  rescue
    e in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, Error.caught(:sima_qian_append_failed, :sima_qian_log_copy_raised, e)}
  end

  defp schema, do: ~s|"eventstore"|

  # Each step (the events' one statement, one table's rows) is its own
  # transaction with a bound well past the pool's 15 s default, which cut
  # the first production fork off and left half its rows (2026-11-26);
  # never unbounded, so a hung step fails rather than holding a
  # connection and a "being made" page forever. The copy as a whole is
  # all or nothing by `remove/1`, not by one long transaction.
  defp q(conn, sql, params), do: Postgrex.query!(conn, sql, params, timeout: @step)
  # Every statement here is built from the catalog's own table and column
  # names and this module's literals, never a request value.
  # sobelow_skip ["SQL.Query"]
  defp rq(sql, params), do: Repo.query!(sql, params, timeout: @step)
  defp platform(fun), do: Scope.platform(fun, timeout: @step)
end
