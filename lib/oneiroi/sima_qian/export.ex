defmodule Oneiroi.SimaQian.Export do
  @moduledoc """
  The resident's streams as `records/events/<day>.jsonl` (spec §6.10):
  every stream that is the resident's (sima-qian #20), its own and its
  conversations', memory's, judgement's, journal's, library's, schedule's
  and the rest, so a rebuild restores the resident and not only its
  identity. `stream` names each line's stream with the resident's id
  taken out: `resident`, `memory`, `conversation-<session key>`.

  One line per event, keys in a fixed order (`sequence`, `stream`,
  `type`, `version`, `at`, `actor`, `data`), data keys sorted, days by
  the event's own instant in UTC, and every day file rewritten whole on
  each run, so an unchanged store exports identical bytes and a change
  shows as exactly the lines it touched. The resident's own uuid never
  appears: every occurrence is written as `$self`, which is what lets a
  rebuild be a new resident and still re-export byte for byte (plan
  P0.7). Fields an event declares `redact:` are written as null, and an
  event declared `export: false` (the export's own bookkeeping) is not
  written at all.

  `sequence` is the line's ordinal among the exported events, dense from
  1, across every stream in the order they were appended: the streams
  are read one by one and merged on the store's own append instant, so
  the export reads this resident's events and never the whole store, and
  a rebuild that appends the lines in order, each append stamped after
  the last, re-exports them in the same order, byte for byte. The resident
  stream's version the export ran through is the backup commit's
  `Oneiroi-Sequence` trailer and the `ExportWritten` event's `through`.

  The export stays a watermark behind capture: an event younger than the
  configured seconds is left for the next run.

  Beside the lines, reading copies rendered from them on the same run
  (`Oneiroi.SimaQian.Readable`, sima-qian #41): the transcripts by day
  and the bookmarks, never read back. What the repository does not carry
  at all is `exceptions/0`, the code's copy of spec §6.10's list.
  """

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Purpose
  alias Oneiroi.SimaQian.Readable

  @self "$self"
  @chunk 1_000
  @page 200

  # The resident's streams, by prefix (sima-qian #20). Every router's
  # prefix is here or in `@not_exported`, which the export test asserts
  # against the routers themselves.
  @streams ~w(resident ethos judgement audits conversation memory ledger library schedule journal governance subscription)

  # Everything of the resident's that the repository does not carry,
  # each with the reason (sima-qian #43). The author's law (spec §6.10):
  # all raw text is in the repository unless there is a really good
  # reason, and this table is the list of reasons. A `:stream` entry is
  # a stream prefix the export leaves out, which `not_exported/0` names
  # and the export test holds against the routers themselves; the rest
  # are what leaves no stream out but still stays in the database, or in
  # Honcho. Spec §6.10's `oneiroi:db-only` list names these same keys,
  # and a test fails when the two drift.
  @not_exported %{
    "regression" =>
      {:stream, "sealed: the resident's own trials, never exported or read (eunomia #12)"},
    "account" => {:stream, "the witness's account, not the resident's"},
    "honcho" =>
      {:stream,
       "the bridge's record of a workspace in Honcho, keyed to the source: a rebuilt resident is a new one and provisions its own on first use (proteus #8), where replaying this would point a copy at the original's memory"},
    "embeddings" =>
      {:derived,
       "the library's chunks and vectors, Honcho's embeddings and every projection table: derived from what the repository holds, rebuilt by replay and an index run, and written in a pattern git does not fit"},
    "witness-only spend" =>
      {:events,
       "ledger events billed under a purpose the resident's own view never shows (drafting, regression; nisaba #4), whose presence in the export would tell her what the unawareness invariant hides"},
    "redacted" =>
      {:fields,
       "fields an event declares `redact:`, the records remote's encrypted token among them: secrets stay in the vault, written as null"},
    "honcho-private" =>
      {:honcho,
       "Honcho's conclusions and summaries drawn from a private, unshared session: withheld from honcho/ as the session's words are from the reading copies (spec §6.3); Honcho keeps them"}
  }

  # An event its module keeps out (the export's own bookkeeping), or one
  # billed under a purpose the resident's own ledger view never shows
  # (nisaba #4): the export is a surface she can reach, and a regression
  # run's calls in it would tell her what the unawareness invariant hides
  # (eunomia #12). Found by that invariant's test the day the ledger was
  # first exported. A rebuild therefore restores no drafting or
  # regression spend and no budget on either; the witness sets those
  # budgets again.
  defp exported?(%{data: %module{} = event}) do
    module.__export__?() and not witness_only?(Map.get(event, :purpose))
  end

  defp witness_only?(nil), do: false

  defp witness_only?(purpose),
    do: Enum.any?(Purpose.witness_only(), &(to_string(&1) == to_string(purpose)))

  @doc "The stream prefixes the export carries."
  @spec streams() :: [String.t()]
  def streams, do: @streams

  @doc "The stream prefixes it does not, each with the reason."
  @spec not_exported() :: %{String.t() => String.t()}
  def not_exported, do: for({name, {:stream, why}} <- @not_exported, into: %{}, do: {name, why})

  @doc "Everything of the resident's the repository does not carry, streams and the rest, each with the reason (spec §6.10)."
  @spec exceptions() :: %{String.t() => String.t()}
  def exceptions, do: Map.new(@not_exported, fn {name, {_what, why}} -> {name, why} end)

  @typedoc "What a run wrote, and the session keys whose words stay the resident's (`Readable.private_sessions/1`)."
  @type result :: %{
          through: non_neg_integer(),
          files: [String.t()],
          private: MapSet.t(String.t())
        }

  @doc "Writes the export under `dir` (the repository root) and returns the last sequence written and the files."
  @spec write(String.t(), Path.t()) :: {:ok, result()}
  # Sobelow reads a `File` call on a built path as a traversal; every path
  # here is the records root (a setting) under a resident id the platform
  # minted, or a clone this code made under the temp dir. No request
  # value reaches a path in this system.
  # sobelow_skip ["Traversal.FileModule"]
  def write(resident_id, dir) do
    cutoff = cutoff()

    events =
      resident_id
      |> events()
      |> Enum.take_while(&(DateTime.compare(&1.data.at, cutoff) != :gt))

    exported =
      events
      |> Enum.filter(&exported?/1)
      |> Enum.with_index(1)

    root = Path.join(dir, "records")
    File.mkdir_p!(Path.join(root, "events"))

    encoded =
      Enum.map(exported, fn {recorded, ordinal} ->
        {recorded, line(recorded, ordinal, resident_id)}
      end)

    files =
      encoded
      |> Enum.group_by(fn {recorded, _line} ->
        Date.to_iso8601(DateTime.to_date(recorded.data.at))
      end)
      |> Enum.sort()
      |> Enum.map(fn {day, days_lines} ->
        path = Path.join(["records", "events", day <> ".jsonl"])
        File.write!(Path.join(dir, path), Enum.map_join(days_lines, "", &(elem(&1, 1) <> "\n")))
        path
      end)

    File.write!(Path.join(root, "README.md"), readme())
    lines = Enum.map(encoded, &Jason.decode!(elem(&1, 1)))
    readable = write_readable(dir, Readable.render(lines))
    identity = identity_files(resident_id, dir)
    own = "resident-" <> resident_id

    through =
      events
      |> Enum.filter(&(&1.stream_uuid == own))
      |> List.last()
      |> then(&if(&1, do: &1.stream_version, else: 0))

    {:ok,
     %{
       through: through,
       files: identity ++ ["records/README.md" | files] ++ readable,
       private: Readable.private_sessions(lines)
     }}
  end

  # The reading copies (sima-qian #41), rewritten whole like the day
  # files; a copy this run did not render is one no line supports any
  # more, and goes. The paths are the renderer's, built from a day and
  # a fixed name, never from a request.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_readable(dir, rendered) do
    paths = Enum.map(rendered, &elem(&1, 0))

    stale =
      Path.wildcard(Path.join([dir, "records", "conversations", "*.md"])) ++
        Path.wildcard(Path.join([dir, "records", "bookmarks.md"]))

    for full <- stale, Path.relative_to(full, dir) not in paths, do: File.rm!(full)

    for {path, content} <- rendered do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end

    paths
  end

  # The identity files (spec §6.2) at the repository root, as last
  # written, so the repository reads as the resident's and a rebuild
  # from `records/events/` reproduces them from their events. The name
  # is one of the aggregate's closed list (`Resident.files/0`), never a
  # request value, which is why the traversal finding is skipped here as
  # on `write/2`.
  # sobelow_skip ["Traversal.FileModule"]
  defp identity_files(resident_id, dir) do
    written =
      for f <- Oneiroi.AgathosDaimon.files(resident_id) do
        File.write!(Path.join(dir, f.name), f.content)
        f.name
      end

    # The build-owned Honcho instructions ride with the soul class
    # (`honcho/`), rendered on every export so a template change lands.
    File.mkdir_p!(Path.join(dir, "honcho"))
    path = Path.join("honcho", "custom-instructions.md")
    File.write!(Path.join(dir, path), Oneiroi.AgathosDaimon.custom_instructions(resident_id))
    written ++ [path]
  end

  @doc "The watermark: the instant an event must be at or before to be exported on this run."
  @spec cutoff() :: DateTime.t()
  def cutoff,
    do: DateTime.add(Clock.now(), -Config.fetch!(:sima_qian, :watermark_seconds), :second)

  @doc "One export line for a recorded event, at `ordinal` among the exported lines."
  @spec line(EventStore.RecordedEvent.t(), pos_integer(), String.t()) :: String.t()
  def line(%EventStore.RecordedEvent{} = recorded, ordinal, resident_id) do
    %module{} = event = recorded.data
    actor = event.actor

    data =
      event
      |> Map.from_struct()
      |> Map.drop([:actor, :at])
      |> Map.new(fn {k, v} ->
        {k, if(k in module.__redact__(), do: nil, else: self(v, resident_id))}
      end)

    Jason.OrderedObject.new(
      sequence: ordinal,
      stream: name(recorded.stream_uuid, resident_id),
      type: type(module),
      version: module.__version__(),
      at: DateTime.to_iso8601(event.at),
      actor:
        Jason.OrderedObject.new(
          kind: actor.kind,
          id: self(actor.id, resident_id),
          model: actor.model
        ),
      data: ordered(data)
    )
    |> Jason.encode!()
  end

  @doc "The wire name of an event module: its name without the `Elixir.` prefix."
  @spec type(module()) :: String.t()
  def type(module), do: module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

  @doc """
  A stream's name in the export: its id with the resident's taken out
  (`resident-<id>` is `resident`, `conversation-<id>-<key>` is
  `conversation-<key>`), which `Rebuild` puts a new id back into.
  """
  @spec name(String.t(), String.t()) :: String.t()
  def name(stream_uuid, resident_id) do
    case String.split(stream_uuid, "-" <> resident_id, parts: 2) do
      [prefix, ""] -> prefix
      [prefix, "-" <> rest] -> prefix <> "-" <> rest
    end
  end

  @doc "Every exported stream's events, merged in the order they were appended."
  @spec events(String.t()) :: [EventStore.RecordedEvent.t()]
  def events(resident_id) do
    resident_id
    |> streams_of()
    |> Enum.flat_map(&(&1 |> stream() |> Enum.to_list()))
    |> Enum.sort_by(&order(&1, resident_id))
  end

  # The append instant, then the stream's name and version, so two
  # streams appended in one microsecond still order the same way on
  # every run and after a rebuild.
  defp order(recorded, resident_id),
    do:
      {DateTime.to_unix(recorded.created_at, :microsecond),
       name(recorded.stream_uuid, resident_id), recorded.stream_version}

  # The resident's streams, found through the store's own search on the
  # id every one of them carries, kept to the exported prefixes. The
  # search is a `LIKE '%<id>%'` over the store's stream table, one row a
  # stream, so it grows with how many streams the store holds and not
  # with its events; unmeasured at any size beyond the suite's.
  defp streams_of(resident_id), do: streams_of(resident_id, 1, [])

  defp streams_of(resident_id, page, acc) do
    {:ok, found} =
      Oneiroi.EventStore.paginate_streams(
        search: "%" <> resident_id <> "%",
        page_size: @page,
        page_number: page
      )

    ids =
      for %{stream_uuid: uuid} <- found.entries,
          name = name_or_nil(uuid, resident_id),
          name && prefix(name) in @streams,
          do: uuid

    if length(found.entries) < @page,
      do: Enum.sort(acc ++ ids),
      else: streams_of(resident_id, page + 1, acc ++ ids)
  end

  defp name_or_nil(uuid, resident_id) do
    if String.contains?(uuid, "-" <> resident_id), do: name(uuid, resident_id)
  end

  @doc "The prefix of a stream's exported name: `conversation-<key>` is `conversation`."
  @spec prefix(String.t()) :: String.t()
  def prefix(name), do: name |> String.split("-", parts: 2) |> hd()

  @doc "One stream by its id, forward, lazily."
  @spec stream(String.t()) :: Enumerable.t()
  def stream(stream_uuid) do
    Stream.resource(
      fn -> 0 end,
      fn
        :done ->
          {:halt, :done}

        from ->
          case Oneiroi.EventStore.read_stream_forward(stream_uuid, from, @chunk) do
            {:ok, []} -> {:halt, :done}
            {:ok, events} when length(events) < @chunk -> {events, :done}
            {:ok, events} -> {events, List.last(events).stream_version + 1}
            {:error, :stream_not_found} -> {:halt, :done}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp ordered(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> {to_string(k), ordered(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp ordered(list) when is_list(list), do: Enum.map(list, &ordered/1)
  defp ordered(other), do: other

  defp self(value, resident_id) when is_binary(value),
    do: String.replace(value, resident_id, @self)

  defp self(map, resident_id) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, self(v, resident_id)} end)

  defp self(list, resident_id) when is_list(list), do: Enum.map(list, &self(&1, resident_id))
  defp self(other, _resident_id), do: other

  defp readme do
    """
    # records

    The resident's own event logs, exported by Oneiroi (spec §6.10): every
    stream that is the resident's, its conversations, memory, judgement,
    journal and library among them. Written by machine, never by hand:
    one JSON object per line under `events/`, one file per UTC day, keys
    and rows in a fixed order, so an unchanged store exports identical
    files. `$self` stands for the resident's own id, and `stream` names a
    line's stream without it; `sequence` numbers the lines from 1 in the
    order they were written. Beside them, reading copies rendered from
    the same lines on every export: `conversations/<day>.md`, each
    session's turns that day, and `bookmarks.md`; never read back, and a
    private session in them is its existence and counts alone. A backup commit's message
    carries `Oneiroi-Sequence`, the stream version the export ran
    through, and `Oneiroi-Root`, a Merkle root over this directory; a
    rebuild replays these files into a fresh store as a new resident and
    tells it where it woke.
    """
  end
end
