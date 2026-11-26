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

  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Rebuild

  @chunk 500

  @doc """
  Copies `from`'s events to `to`; `metadata` joins each line's own.
  `drop` leaves out events of the named types (the fork's own mark, at a
  cutover). Returns how many were copied and the last of `from`'s
  resident-stream versions it held.
  """
  @spec copy(String.t(), String.t(), map(), [module()]) ::
          {:ok, %{events: non_neg_integer(), sequence: non_neg_integer()}} | {:error, term()}
  def copy(from, to, metadata, drop \\ []) do
    events = from |> Export.events() |> Enum.reject(&(event_module(&1) in drop))

    with :ok <- append(events, from, to, metadata) do
      sequence =
        events
        |> Enum.filter(&(&1.stream_uuid == "resident-" <> from))
        |> List.last()
        |> then(&if(&1, do: &1.stream_version, else: 0))

      {:ok, %{events: length(events), sequence: sequence}}
    end
  end

  defp append(events, from, to, metadata) do
    events
    |> Enum.chunk_by(& &1.stream_uuid)
    |> Enum.flat_map(&Enum.chunk_every(&1, @chunk))
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
        |> Map.drop(["fork_of", "imported", "cutover"])
        |> Map.merge(metadata)
    }
  end

  defp event_module(%{data: %module{}}), do: module
  defp event_module(_recorded), do: nil
end
