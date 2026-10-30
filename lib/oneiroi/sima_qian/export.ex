defmodule Oneiroi.SimaQian.Export do
  @moduledoc """
  The resident's stream as `records/events/<day>.jsonl` (spec §6.10).

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
  1, not the event's stream version: the stream has gaps where the
  bookkeeping sits, a rebuild replays the lines densely, and the two
  exports are byte-identical only if the ordinal is what is written. The
  stream version the export ran through is the backup commit's
  `Oneiroi-Sequence` trailer and the `ExportWritten` event's `through`.

  The export stays a watermark behind capture: an event younger than the
  configured seconds is left for the next run.
  """

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config

  @self "$self"
  @chunk 1_000

  @type result :: %{through: non_neg_integer(), files: [String.t()]}

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
      resident_id |> stream() |> Enum.take_while(&(DateTime.compare(&1.data.at, cutoff) != :gt))

    exported =
      events
      |> Enum.filter(fn %{data: %module{}} -> module.__export__?() end)
      |> Enum.with_index(1)

    root = Path.join(dir, "records")
    File.mkdir_p!(Path.join(root, "events"))

    files =
      exported
      |> Enum.group_by(fn {recorded, _ordinal} ->
        Date.to_iso8601(DateTime.to_date(recorded.data.at))
      end)
      |> Enum.sort()
      |> Enum.map(fn {day, days_events} ->
        path = Path.join(["records", "events", day <> ".jsonl"])

        body =
          Enum.map_join(days_events, "", fn {recorded, ordinal} ->
            line(recorded, ordinal, resident_id) <> "\n"
          end)

        File.write!(Path.join(dir, path), body)
        path
      end)

    File.write!(Path.join(root, "README.md"), readme())
    identity = identity_files(resident_id, dir)
    through = events |> List.last() |> then(&if(&1, do: &1.stream_version, else: 0))
    {:ok, %{through: through, files: identity ++ ["records/README.md" | files]}}
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
      stream: "resident",
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

  @doc "The resident's own stream, forward, lazily."
  @spec stream(String.t()) :: Enumerable.t()
  def stream(resident_id) do
    Stream.resource(
      fn -> 0 end,
      fn
        :done ->
          {:halt, :done}

        from ->
          case Oneiroi.EventStore.read_stream_forward("resident-" <> resident_id, from, @chunk) do
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

    The resident's own event log, exported by Oneiroi (spec §6.10). Written
    by machine, never by hand: one JSON object per line under `events/`,
    one file per UTC day, keys and rows in a fixed order, so an unchanged
    store exports identical files. `$self` stands for the resident's own
    id; `sequence` numbers the lines from 1. A backup commit's message
    carries `Oneiroi-Sequence`, the stream version the export ran
    through, and `Oneiroi-Root`, a Merkle root over this directory; a
    rebuild replays these files into a fresh store as a new resident and
    tells it where it woke.
    """
  end
end
