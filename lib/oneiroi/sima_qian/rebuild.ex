defmodule Oneiroi.SimaQian.Rebuild do
  @moduledoc """
  Rebuild is replay (spec §6.10, §9): a repository's `records/events/`
  written into a fresh stream under a new resident id, then an `Imported`
  event naming the source, whether the attestation held, and the root it
  was read at, and custody to the importing steward. The platform cannot
  tell a move from a copy, so an import is always a new resident and
  never a fork (spec §6.2); a store that already holds a resident from
  that repository at that root refuses.

  What cannot come back is printed by name: nothing in P0, since the only
  state is the log; the migration's transfer list grows with the systems.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Merkle

  @self "$self"
  @chunk 500

  # The clone directory is this function's own, under the temp dir; the
  # `File.rm_rf` on it is what sobelow reads as a traversal.
  # sobelow_skip ["Traversal.FileModule"]
  def run(url, steward_account_id, %Actor{} = actor) do
    clone = Path.join(System.tmp_dir!(), "oneiroi-rebuild-#{System.unique_integer([:positive])}")

    try do
      with :ok <- Git.clone(url, clone),
           {attestation, root, sequence} <- attestation(clone),
           :ok <- refuse_if_imported(url, root),
           {:ok, lines} <- read_lines(clone),
           id = Ecto.UUID.generate(),
           :ok <- append(id, lines),
           {:ok, _} <- import_event(id, url, attestation, root, sequence, actor),
           {:ok, _} <- custody(id, steward_account_id, actor) do
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

  defp refuse_if_imported(url, root) do
    case Scope.platform(fn -> Store.imported(url, root) end) do
      nil -> :ok
      _row -> {:error, Error.new(:sima_qian_already_imported, source: url, root: root)}
    end
  end

  # The paths are a wildcard over the clone this function's caller just
  # made under the system temp dir, never a request value.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_lines(clone) do
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

  # The events as recorded, re-keyed to the new resident; the serializer
  # upcasts an older version on read, so the data is written as the file
  # holds it and never reshaped here.
  defp append(id, lines) do
    lines
    |> Enum.map(&event_data(&1, id))
    |> Enum.chunk_every(@chunk)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case Oneiroi.EventStore.append_to_stream("resident-" <> id, :any_version, chunk) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:append, reason}}}
      end
    end)
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

  defp import_event(id, url, attestation, root, sequence, actor) do
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

  defp custody(id, steward_account_id, actor) do
    Router.dispatch(%Commands.TransferCustody{
      actor: actor,
      at: Clock.now(),
      id: id,
      to: {:account, steward_account_id},
      note: "rebuilt from the repository and placed with the importing steward"
    })
  end
end
