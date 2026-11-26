defmodule Oneiroi.SimaQian.Transplant do
  @moduledoc """
  A resident's life moved under another id, byte for byte (sima-qian#67,
  #68): every event of her exported streams, raw as the store holds it,
  in the order it was appended, re-keyed from one id to the other and
  appended to the same streams under the other. Raw, never through the
  export: the export writes redacted fields as null (an adapter's token
  hash, the records remote's token) and leaves out witness-only spend,
  and a copy made from it would not be her.

  The fork is this from her to a new id with `fork_of` on every line; a
  succession's cutover is this from the fork back to her own id, after
  her streams are replaced (`Oneiroi.SimaQian.Cutover`).
  """

  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Rebuild

  @read 500

  @doc """
  Copies `from`'s events to `to`; `metadata` joins each line's own.
  `drop` leaves out events of the named types (the fork's own mark, at a
  cutover). Returns how many were copied and the last of `from`'s
  resident-stream versions it held.

  Streamed and throttled (sima-qian#71; 2026-11-26, a fork of her whole
  life read every event into memory and appended them back to back, and
  the projectors folding them starved the event store's pool and took
  the app down): her events are read off the log in the order they were
  appended, a page at a time up to where the log stood when the copy
  began, and appended `SIMA_QIAN_TRANSPLANT_BATCH` at a time with
  `SIMA_QIAN_TRANSPLANT_PAUSE_MS` between batches.
  """
  @spec copy(String.t(), String.t(), map(), [module()]) ::
          {:ok, %{events: non_neg_integer(), sequence: non_neg_integer()}} | {:error, term()}
  def copy(from, to, metadata, drop \\ []) do
    wanted = MapSet.new(Export.stream_uuids(from))
    batch = Config.fetch!(:sima_qian, :transplant_batch)
    pause = Config.fetch!(:sima_qian, :transplant_pause_ms)

    head()
    |> then(
      &(Oneiroi.EventStore.stream_all_forward(0, read_batch_size: @read)
        |> Stream.take_while(fn e -> e.event_number <= &1 end))
    )
    |> Stream.filter(&(MapSet.member?(wanted, &1.stream_uuid) and event_module(&1) not in drop))
    |> Stream.chunk_every(batch)
    |> Enum.reduce_while(
      {:ok, %{events: 0, sequence: 0}},
      &batch(&1, &2, {from, to, metadata}, pause)
    )
  end

  defp batch(events, {:ok, acc}, {from, to, metadata}, pause) do
    case append(events, from, to, metadata) do
      :ok ->
        if pause > 0, do: Process.sleep(pause)
        {:cont, {:ok, tally(acc, events, from)}}

      failed ->
        {:halt, failed}
    end
  end

  # Where the log stood when the copy began: the copy's own appends, past
  # it, are never read back.
  defp head do
    case Oneiroi.EventStore.read_all_streams_backward(-1, 1) do
      {:ok, [last]} -> last.event_number
      _empty -> 0
    end
  end

  defp tally(acc, events, from) do
    last =
      events
      |> Enum.filter(&(&1.stream_uuid == "resident-" <> from))
      |> List.last()

    %{
      events: acc.events + length(events),
      sequence: if(last, do: last.stream_version, else: acc.sequence)
    }
  end

  defp append(events, from, to, metadata) do
    events
    |> Enum.chunk_by(& &1.stream_uuid)
    |> Enum.reduce_while(:ok, fn run, :ok ->
      case append_run(run, from, to, metadata) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error, Error.caught(:sima_qian_append_failed, :sima_qian_transplant_append, reason)}}
      end
    end)
  end

  defp append_run([first | _] = run, from, to, metadata) do
    uuid = first.stream_uuid |> Export.name(from) |> Rebuild.stream_uuid(to)

    Oneiroi.EventStore.append_to_stream(
      uuid,
      :any_version,
      Enum.map(run, &event_data(&1, from, to, metadata))
    )
  end

  # The data as recorded, with every mention of the one id written as the
  # other: the id is a UUID, so a string match is the id and only the id.
  defp event_data(recorded, from, to, metadata) do
    data =
      recorded.data
      |> Jason.encode!()
      |> String.replace(from, to)
      |> Jason.decode!()

    %EventStore.EventData{
      event_type: recorded.event_type,
      data: data,
      # A move's own markers are this move's: the fork's `fork_of` does not
      # ride the cutover back.
      metadata:
        recorded.metadata
        |> Kernel.||(%{})
        |> Map.drop(["fork_of", "imported", "cutover", "transplanted"])
        |> Map.merge(metadata)
        # Handlers pass over it (sima-qian#69): a move is not a deed.
        |> Map.put("transplanted", true)
    }
  end

  defp event_module(%{data: %module{}}), do: module
  defp event_module(_recorded), do: nil
end
