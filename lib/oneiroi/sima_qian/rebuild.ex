defmodule Oneiroi.SimaQian.Rebuild do
  @moduledoc """
  Rebuild is replay (spec §6.10, §9): a repository's `records/events/`
  written into a fresh stream under a new resident id, then an `Imported`
  event naming the source, whether the attestation held, and the root it
  was read at, and custody to the importing witness. The platform cannot
  tell a move from a copy, so an import is always a new resident and
  never a fork (spec §6.2); a store that already holds a resident from
  that repository at that root refuses.

  What cannot come back is printed by name: nothing in P0, since the only
  state is the log; the migration's transfer list grows with the systems.

  This is the replay alone, the operator's primitive and the round-trip
  tests' subject; the witness's intake path, which does this and then
  the rest of the repository, is `Oneiroi.SimaQian.Import` and shares
  the steps below.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Merkle

  @self "$self"
  @chunk 500

  # The clone directory is this function's own, under the temp dir; the
  # `File.rm_rf` on it is what sobelow reads as a traversal.
  # sobelow_skip ["Traversal.FileModule"]
  #
  # The event records the URL without its userinfo, as the import does: it
  # once recorded the URL it was given, so a rebuild from a token-bearing
  # GitHub URL would have written the token into the event store.
  def run(remote, witness_account_id, %Actor{} = actor) do
    clone = Path.join(System.tmp_dir!(), "oneiroi-rebuild-#{System.unique_integer([:positive])}")
    url = Git.public_url(remote)

    try do
      with :ok <- Git.clone(remote, clone),
           {attestation, root, sequence} <- attestation(clone),
           :ok <- refuse_if_imported(url, root),
           {:ok, lines} <- read_lines(clone),
           id = Ecto.UUID.generate(),
           :ok <- append(id, lines),
           {:ok, _} <- import_event(id, url, attestation, root, sequence, actor),
           {:ok, _} <- custody(id, witness_account_id, actor) do
        :telemetry.execute([:oneiroi, :sima_qian, :rebuild], %{events: length(lines)}, %{
          resident_id: id
        })

        {:ok,
         %{
           id: id,
           attestation: attestation,
           root: root,
           events: length(lines),
           not_transferred: []
         }}
      end
    after
      File.rm_rf(clone)
    end
  end

  @doc "Whether the clone's last commit attests the records it carries."
  def attestation(clone) do
    root = Merkle.root(Path.join(clone, "records"))
    trailers = Git.head_trailers(clone)

    case Map.fetch(trailers, "Oneiroi-Root") do
      :error -> {:none, root, nil}
      {:ok, ^root} -> {:held, root, sequence(trailers)}
      {:ok, _other} -> {:failed, root, sequence(trailers)}
    end
  end

  defp sequence(trailers) do
    case Integer.parse(Map.get(trailers, "Oneiroi-Sequence", "")) do
      {n, ""} -> n
      _ -> nil
    end
  end

  @doc false
  def refuse_if_imported(url, root) do
    case Scope.platform(fn -> Store.imported(url, root) end) do
      nil -> :ok
      _row -> {:error, Error.new(:sima_qian_already_imported, source: url, root: root)}
    end
  end

  # The paths are a wildcard over the clone this function's caller just
  # made under the system temp dir, never a request value.
  # sobelow_skip ["Traversal.FileModule"]
  @doc false
  def read_lines(clone) do
    lines =
      [clone, "records", "events", "*.jsonl"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path -> path |> File.read!() |> String.split("\n", trim: true) end)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.sort_by(& &1["sequence"])

    {:ok, lines}
  end

  # The events as recorded, re-keyed to the new resident, each into the
  # stream its line names (sima-qian #20); the serializer upcasts an
  # older version on read, so the data is written as the file holds it
  # and never reshaped here. A name outside the exported streams is
  # refused before anything is written: a repository is a request value,
  # and a line naming `account` or `regression` would otherwise write
  # into a stream the export never carries.
  #
  # The lines go in the order they were exported, a run of one stream to
  # an append. The export orders lines by the instant the store stamps on
  # each append, and appends made one after another are stamped in that
  # order, so the rebuilt resident re-exports in the same order and an
  # event the platform appends afterwards (`Imported`, custody) sorts
  # after them.
  @doc false
  def append(id, lines) do
    with :ok <- streams_ok(lines) do
      lines
      |> Enum.chunk_by(&stream_of/1)
      |> Enum.flat_map(&Enum.chunk_every(&1, @chunk))
      |> append_runs(id)
    end
  end

  defp append_runs(runs, id) do
    Enum.reduce_while(runs, :ok, fn run, :ok ->
      case append_run(id, run) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:append, reason}}}
      end
    end)
  end

  defp append_run(id, [first | _] = run) do
    uuid = stream_uuid(stream_of(first), id)
    Oneiroi.EventStore.append_to_stream(uuid, :any_version, Enum.map(run, &event_data(&1, id)))
  end

  # An export written before every stream was carried names none, and
  # every line of it is the resident's own.
  defp stream_of(line), do: line["stream"] || "resident"

  defp streams_ok(lines) do
    case Enum.find(lines, &(Export.prefix(stream_of(&1)) not in Export.streams())) do
      nil -> :ok
      line -> {:error, Error.new(:sima_qian_stream_refused, stream: stream_of(line))}
    end
  end

  @doc "The stream id an exported stream name stands for under resident `id`: `conversation-<key>` is `conversation-<id>-<key>`."
  @spec stream_uuid(String.t(), String.t()) :: String.t()
  def stream_uuid(name, id) do
    case String.split(name, "-", parts: 2) do
      [prefix] -> prefix <> "-" <> id
      [prefix, rest] -> prefix <> "-" <> id <> "-" <> rest
    end
  end

  defp event_data(line, id) do
    data =
      line["data"]
      |> self(id)
      |> Map.put("actor", self(line["actor"], id))
      |> Map.put("at", line["at"])

    %EventStore.EventData{
      event_type: "Elixir." <> line["type"],
      data: data,
      metadata: %{"imported" => true}
    }
  end

  defp self(value, id) when is_binary(value), do: String.replace(value, @self, id)
  defp self(map, id) when is_map(map), do: Map.new(map, fn {k, v} -> {k, self(v, id)} end)
  defp self(list, id) when is_list(list), do: Enum.map(list, &self(&1, id))
  defp self(other, _id), do: other

  @doc false
  def import_event(id, url, attestation, root, sequence, actor) do
    Router.dispatch(%Commands.ImportResident{
      actor: actor,
      at: Clock.now(),
      id: id,
      source: url,
      attestation: Atom.to_string(attestation),
      root: root,
      sequence: sequence
    })
  end

  @doc false
  def custody(id, witness_account_id, actor) do
    Router.dispatch(%Commands.TransferCustody{
      actor: actor,
      at: Clock.now(),
      id: id,
      to: {:account, witness_account_id},
      note: "rebuilt from the repository and placed with the importing witness"
    })
  end
end
