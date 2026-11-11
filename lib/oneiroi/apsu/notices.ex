defmodule Oneiroi.Apsu.Notices do
  @moduledoc """
  Change notices (apsu#24): after a projection commits, the client is
  told which of a resident's records changed, never the data, so a
  mounted screen refetches only what moved (design/ui-server-work.md
  S1). A notice is `%{kind, stream, ref, position}`:

  - `kind` is the event's short name (`BookmarkAdded`);
  - `stream` is its stream with the resident's id taken out, as the
    export names it (`memory`, `conversation-<key>`);
  - `ref` is the record the event names (its number, path, key or day),
    or nil;
  - `position` is the event's place in the store's global order, the
    cursor a client keeps and resumes from.

  `projected/3` is called by every projector after its transaction
  commits (`Oneiroi.Projection`), so a notice never runs ahead of the
  row it announces. An event several projectors fold is announced once
  by each; the client coalesces on `position`. A stream that is not a
  resident's, or whose prefix is sealed (the regression stream,
  eunomia#12), is never announced. Nothing here may stop a projector:
  any failure is swallowed and logged.

  `since/2` replays what a resident missed from a cursor, reading the
  store's global order forward. Past `@scan` events read or `@cap`
  notices found it answers `:reset`, and the client refetches whatever
  it shows.
  """

  require Logger

  alias Oneiroi.Apsu.Error
  alias Oneiroi.Apsu.PubSub

  @uuid ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
  @sealed ~w(regression)
  @ref_fields [:number, :path, :key, :day, :session_key]

  # Bounds, guesses not measured: how far a replay reads the global
  # order, and how many notices it hands back, before saying reset.
  @scan 5_000
  @cap 500

  @type notice :: %{
          kind: String.t(),
          stream: String.t(),
          ref: String.t() | nil,
          position: non_neg_integer()
        }

  @doc "Announces a folded event to its resident's subscribers; always :ok."
  @spec projected(String.t(), struct(), map()) :: :ok
  def projected(_projection, event, metadata) do
    with stream when is_binary(stream) <- Map.get(metadata, :stream_id),
         {:ok, resident_id, name} <- owner(stream),
         position when is_integer(position) <- Map.get(metadata, :event_number) do
      PubSub.broadcast(:apsu, :notices, {resident_id, notice(event, name, position)})
    else
      _not_a_resident_stream -> :ok
    end
  rescue
    # A notice is a convenience; the row is already committed. Named in
    # the log by its class, never raised into the projector (apsu#21).
    exception ->
      e = Error.caught(:apsu_notice_failed, :apsu_notices_projected, exception)
      Logger.warning("apsu: a change notice was not sent", Oneiroi.Error.metadata(e))
      :ok
  end

  @doc """
  The notices for `resident_id` after `position`, oldest first, or
  `:reset` when the gap is too wide to replay.
  """
  @spec since(String.t(), non_neg_integer()) :: {:ok, [notice()]} | :reset
  def since(resident_id, position) when is_integer(position) and position >= 0 do
    read =
      (position + 1)
      |> Oneiroi.EventStore.stream_all_forward(read_batch_size: 500)
      |> Enum.take(@scan + 1)

    found =
      for recorded <- Enum.take(read, @scan),
          {:ok, ^resident_id, name} <- [owner(recorded.stream_uuid)],
          do: notice(recorded.data, name, recorded.event_number)

    if length(read) > @scan or length(found) > @cap, do: :reset, else: {:ok, found}
  end

  @doc "The store's latest global position, or 0 for an empty store."
  @spec head() :: non_neg_integer()
  def head do
    case -1 |> Oneiroi.EventStore.stream_all_backward(read_batch_size: 1) |> Enum.take(1) do
      [recorded] -> recorded.event_number
      [] -> 0
    end
  end

  @doc "Whose stream this is, and its name with the resident's id taken out."
  @spec owner(String.t()) :: {:ok, String.t(), String.t()} | :none
  def owner(stream_uuid) do
    with [resident_id] <- Regex.run(@uuid, stream_uuid),
         [prefix | _] <- String.split(stream_uuid, "-" <> resident_id, parts: 2),
         name = String.trim_trailing(prefix, "-"),
         false <- name == "" or hd(String.split(name, "-")) in @sealed do
      {:ok, resident_id, name}
    else
      _ -> :none
    end
  end

  defp notice(event, stream, position) do
    %{kind: kind(event), stream: stream, ref: ref(event), position: position}
  end

  defp kind(%{__struct__: module}), do: module |> Module.split() |> List.last()
  defp kind(_data), do: nil

  defp ref(%{} = event) do
    Enum.find_value(@ref_fields, fn field ->
      case Map.get(event, field) || Map.get(event, Atom.to_string(field)) do
        nil -> nil
        value when is_binary(value) -> value
        value when is_integer(value) -> Integer.to_string(value)
        _other -> nil
      end
    end)
  end
end
