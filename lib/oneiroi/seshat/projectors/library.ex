defmodule Oneiroi.Seshat.Projectors.Library do
  @moduledoc "Folds the library streams into the document rows' identity and provenance, the publications, the discussions."
  use Oneiroi.Projection, name: "seshat_library"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Kinds

  alias Oneiroi.Seshat.Store.{
    Chunk,
    Digest,
    Discussion,
    Document,
    DocumentMove,
    External,
    Oracle,
    Reference,
    Research
  }

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
        kind: Kinds.released(e.kind),
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

  # Archived (seshat#45): a row for the archived copy, the old row made
  # the tombstone, the old chunks gone; the index reads neither again.
  fold(%Events.DocumentArchived{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :archived,
      %Document{
        resident_id: e.id,
        path: e.to,
        kind: "archive",
        origin: "archived",
        bytes: e.archived_bytes,
        versions: 1,
        registered_at: e.at,
        written_at: e.at,
        written_by_kind: actor_kind(e.actor)
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :path]
    )
    |> Multi.update_all(
      :tombstone,
      from(d in Document, where: d.resident_id == ^e.id and d.path == ^e.path),
      set: [kind: "tombstone", bytes: e.tombstone_bytes, written_at: e.at]
    )
    |> Multi.delete_all(
      :chunks,
      from(c in Chunk, where: c.resident_id == ^e.id and c.path == ^e.path)
    )
  end)

  # Moved (seshat#39): the row, its chunks and its edges are re-keyed to
  # the new path, so the move costs no embedding (the bytes are the
  # same); the edges stay only if the new kind mints them. The move
  # itself is a row, which a citation of the old path follows.
  fold(%Events.DocumentMoved{} = e, _metadata, fn multi ->
    cites? = match?(%{cites: true}, Enum.find(Kinds.all(), &(&1.kind == e.to_kind)))
    refs = from(r in Reference, where: r.resident_id == ^e.id and r.from_path == ^e.from)

    multi
    |> Multi.update_all(
      :document,
      from(d in Document, where: d.resident_id == ^e.id and d.path == ^e.from),
      set: [path: e.to, kind: Kinds.released(e.to_kind)]
    )
    |> Multi.update_all(
      :chunks,
      from(c in Chunk, where: c.resident_id == ^e.id and c.path == ^e.from),
      set: [path: e.to]
    )
    |> then(fn m ->
      if cites?,
        do: Multi.update_all(m, :references, refs, set: [from_path: e.to, from_kind: e.to_kind]),
        else: Multi.delete_all(m, :references, refs)
    end)
    |> Multi.insert(
      :move,
      %DocumentMove{
        resident_id: e.id,
        from_path: e.from,
        to_path: e.to,
        moved_at: e.at,
        moved_by_kind: actor_kind(e.actor)
      },
      on_conflict: {:replace, [:to_path, :moved_at, :moved_by_kind]},
      conflict_target: [:resident_id, :from_path]
    )
  end)

  # Removed (seshat#33): the row, its chunks and the edges it minted go;
  # the stream keeps that it was, by whom.
  fold(%Events.DocumentRemoved{} = e, _metadata, fn multi ->
    multi
    |> Multi.delete_all(
      :document,
      from(d in Document, where: d.resident_id == ^e.id and d.path == ^e.path)
    )
    |> Multi.delete_all(
      :chunks,
      from(c in Chunk, where: c.resident_id == ^e.id and c.path == ^e.path)
    )
    |> Multi.delete_all(
      :references,
      from(r in Reference, where: r.resident_id == ^e.id and r.from_path == ^e.path)
    )
  end)

  fold(%Events.DocumentAdopted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :document,
      %Document{
        resident_id: e.id,
        path: e.path,
        kind: Kinds.released(e.kind),
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

  fold(%Events.KeepsakeRegistered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :registered,
      from(d in Document, where: d.resident_id == ^e.id and d.path == ^e.path),
      set: [kind: "keepsake"]
    )
  end)

  fold(%Events.KeepsakeNoted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :noted,
      from(d in Document, where: d.resident_id == ^e.id and d.path == ^e.path),
      set: [note: e.note, noted_at: e.at]
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

  # ---- the oracle (seshat#34) ----

  fold(%Events.OracleDispatched{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:oracle, e.number},
      %Oracle{
        resident_id: e.id,
        number: e.number,
        question: e.question,
        sources: e.sources || [],
        session_key: e.session_key,
        asked_by: actor_kind(e.actor) || "platform",
        status: "open",
        dispatched_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.OracleAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:oracle, e.number},
      from(o in Oracle, where: o.resident_id == ^e.id and o.number == ^e.number),
      set: [
        status: "answered",
        path: e.path,
        confidence: e.confidence,
        read: e.read || [],
        used: e.used || [],
        model: e.model,
        settled_at: e.at
      ]
    )
  end)

  fold(%Events.OracleFailed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:oracle, e.number},
      from(o in Oracle, where: o.resident_id == ^e.id and o.number == ^e.number),
      set: [status: "failed", reason: e.reason, settled_at: e.at]
    )
  end)

  # ---- external sources (seshat#46) ----

  fold(%Events.ExternalCommissioned{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:external, e.number},
      %External{
        resident_id: e.id,
        number: e.number,
        kind: e.kind,
        key: e.key,
        url: e.url,
        ref: e.ref,
        status: "asked",
        session_key: e.session_key,
        commissioned_by: actor_kind(e.actor) || "platform",
        commissioned_at: e.at,
        asked_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.ExternalFetchAsked{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:external, e.number},
      from(x in External, where: x.resident_id == ^e.id and x.number == ^e.number),
      set: [status: "asked", asked_at: e.at, session_key: e.session_key, reason: nil]
    )
  end)

  # The copy before this one is kept by its digest and instant, so the
  # resident is told whether the new copy differs and since when.
  fold(%Events.ExternalFetched{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:external, e.number},
      from(x in External,
        where: x.resident_id == ^e.id and x.number == ^e.number,
        update: [
          set: [
            previous_hash: x.content_hash,
            previous_fetched_at: x.fetched_at,
            status: "fetched",
            path: ^e.path,
            title: ^e.title,
            content_hash: ^e.content_hash,
            commit: ^e.commit,
            bytes: ^e.bytes,
            fetched_at: ^e.at,
            reason: nil
          ],
          inc: [fetches: 1]
        ]
      ),
      []
    )
  end)

  fold(%Events.ExternalFetchFailed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:external, e.number},
      from(x in External, where: x.resident_id == ^e.id and x.number == ^e.number),
      set: [status: "failed", reason: e.reason]
    )
  end)

  # ---- research (seshat#38) ----

  fold(%Events.ResearchAsked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:research, e.number},
      %Research{
        resident_id: e.id,
        number: e.number,
        question: e.question,
        urls: e.urls || [],
        session_key: e.session_key,
        asked_by: actor_kind(e.actor) || "platform",
        status: "open",
        asked_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.ResearchAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:research, e.number},
      from(r in Research, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [status: "answered", path: e.path, sources: e.sources || [], settled_at: e.at]
    )
  end)

  fold(%Events.ResearchFailed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:research, e.number},
      from(r in Research, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [status: "failed", reason: e.reason, settled_at: e.at]
    )
  end)

  fold(%Events.DigestAsked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      {:digest, e.number},
      %Digest{
        resident_id: e.id,
        number: e.number,
        session_key: e.session_key,
        since: e.since,
        asked_by: actor_kind(e.actor) || "platform",
        status: "open",
        asked_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.DigestAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:digest, e.number},
      from(d in Digest, where: d.resident_id == ^e.id and d.number == ^e.number),
      set: [status: "answered", path: e.path, items: e.items || 0, settled_at: e.at]
    )
  end)

  fold(%Events.DigestFailed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:digest, e.number},
      from(d in Digest, where: d.resident_id == ^e.id and d.number == ^e.number),
      set: [status: "failed", reason: e.reason, settled_at: e.at]
    )
  end)

  defp actor_kind(%{kind: kind}), do: Atom.to_string(kind)
  defp actor_kind(_other), do: nil

  # An original's provenance (seshat#28): built with atom keys, read back
  # from the log with string keys; nil on every other adoption.
  defp provenance(%{provenance: %{} = p}, key),
    do: Map.get(p, key) || Map.get(p, String.to_existing_atom(key))

  defp provenance(_event, _key), do: nil
end
