defmodule Oneiroi.Seshat.Projectors.Library do
  @moduledoc "Folds the library streams into the document rows' identity and provenance, the publications, the discussions."
  use Oneiroi.Projection, name: "seshat_library"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.{Discussion, Document}

  # A write sets the provenance columns and leaves the index's own
  # (hash, title, status, embedded_with, indexed_at, chunks) to the next
  # run: `on_conflict` names exactly what the stream knows. The hash in
  # particular is what the index last read, not what was last written:
  # the first version set it here, so a rewrite's run found the row's
  # hash already equal to the file's and embedded nothing, and the suite
  # read a stale status off a file it had just changed.
  fold(%Events.DocumentWritten{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :document,
      %Document{
        resident_id: e.id,
        path: e.path,
        kind: e.kind,
        origin: "written",
        bytes: e.bytes,
        versions: 1,
        registered_at: e.at,
        written_at: e.at,
        written_by_kind: actor_kind(e.actor)
      },
      on_conflict: [
        set: [
          bytes: e.bytes,
          written_at: e.at,
          written_by_kind: actor_kind(e.actor),
          missing_at: nil
        ],
        inc: [versions: 1]
      ],
      conflict_target: [:resident_id, :path]
    )
  end)

  fold(%Events.DocumentAdopted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :document,
      %Document{
        resident_id: e.id,
        path: e.path,
        kind: e.kind,
        origin: "adopted",
        bytes: e.bytes,
        versions: 1,
        registered_at: e.at,
        written_at: e.at,
        written_by_kind: actor_kind(e.actor),
        source_repo: provenance(e, "source"),
        source_commit: provenance(e, "commit"),
        source_path: provenance(e, "path"),
        source_blob: provenance(e, "blob")
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :path]
    )
  end)

  fold(%Events.PiecePublished{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :published,
      from(d in Document, where: d.resident_id == ^e.id and d.path == ^e.path),
      set: [published_url: e.url, published_at: e.at]
    )
  end)

  fold(%Events.DiscussionOpened{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :discussion,
      %Discussion{resident_id: e.id, path: e.path, session_key: e.session_key, opened_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id, :path, :session_key]
    )
  end)

  defp actor_kind(%{kind: kind}), do: Atom.to_string(kind)
  defp actor_kind(_other), do: nil

  # An original's provenance (seshat #28): built with atom keys, read back
  # from the log with string keys; nil on every other adoption.
  defp provenance(%{provenance: %{} = p}, key),
    do: Map.get(p, key) || Map.get(p, String.to_existing_atom(key))

  defp provenance(_event, _key), do: nil
end
