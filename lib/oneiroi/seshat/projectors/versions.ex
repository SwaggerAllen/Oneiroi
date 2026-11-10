defmodule Oneiroi.Seshat.Projectors.Versions do
  @moduledoc """
  Folds the library stream into each path's recorded versions (seshat
  #54): every write, adoption, move and archive, with the hash it left
  the path at, who did it, when, and the writer's note. The words are
  the repository's; these rows are what joins a commit's blob to the act
  and the actor that made it. A projector of its own, so it folds the
  stream from its origin and every version written before it existed
  has its row.
  """
  use Oneiroi.Projection, name: "seshat_versions"

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.DocumentVersion

  fold(%Events.DocumentWritten{} = e, metadata, fn multi ->
    version(multi, :written, e, metadata, e.path, e.hash, e.bytes, e.note)
  end)

  fold(%Events.DocumentAdopted{} = e, metadata, fn multi ->
    version(multi, :adopted, e, metadata, e.path, e.hash, e.bytes, nil)
  end)

  fold(%Events.DocumentMoved{} = e, metadata, fn multi ->
    version(multi, :moved, e, metadata, e.to, e.hash, nil, "moved from #{e.from}")
  end)

  fold(%Events.DocumentArchived{} = e, metadata, fn multi ->
    multi
    |> version(:archived, e, metadata, e.to, e.archived_hash, e.archived_bytes, e.why)
    |> version(
      :tombstone,
      e,
      metadata,
      e.path,
      e.tombstone_hash,
      e.tombstone_bytes,
      "archived to #{e.to}: #{e.why}"
    )
  end)

  defp version(multi, act, e, metadata, path, hash, bytes, note) do
    Multi.insert(
      multi,
      {:version, act},
      %DocumentVersion{
        resident_id: e.id,
        path: path,
        event_number: Map.get(metadata, :event_number, 0),
        act: Atom.to_string(act),
        hash: hash,
        bytes: bytes,
        actor_kind: actor(e.actor, :kind),
        actor_id: actor(e.actor, :id),
        note: note,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :path, :event_number]
    )
  end

  defp actor(%{} = actor, key) do
    case Map.get(actor, key) || Map.get(actor, Atom.to_string(key)) do
      nil -> nil
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  end

  defp actor(_none, _key), do: nil
end
