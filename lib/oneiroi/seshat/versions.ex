defmodule Oneiroi.Seshat.Versions do
  @moduledoc """
  A document's versions, the diff between two, and a restore (seshat
  #54, design/ui-server-work.md S4).

  The words of a version are the repository's: the commits that changed
  the path (`Oneiroi.SimaQian.repository_history/3`) and the file on
  disk now. Who made each version, when and with what note is the
  library stream's (`Projectors.Versions`). The two are joined by the
  content's SHA-256, the hash every document event already carries, so
  a version is named by that hash: the same words written twice are one
  version with two acts, and any commit holding them gives them back.

  A recorded act whose words no commit holds and the file no longer has
  (written and overwritten between two nightly backups) is listed, not
  restorable. A commit no act explains (an identity file, a file written
  before the library recorded it) is listed with no actor and the
  commit's subject as its note.

  A restore is the write the normal path makes: a library document is
  written again through the flow, a restore note on its version; an
  identity file goes through `AgathosDaimon.write_file/5`, and after
  first contact, where that answers that a witness's edit is a
  proposal, it is filed as the soul-edit proposal the Files screen
  would file (spec §6.2).
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Leases
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian

  @doc "The versions of a path, newest first, and the hash of the file on disk now (nil when there is none)."
  def list(resident_id, path) do
    with {:ok, path} <- path(resident_id, path),
         {:ok, commits} <- commits(resident_id, path) do
      current = current(resident_id, path)
      rows = Scope.resident(resident_id, fn -> Store.versions(path) end)

      held =
        MapSet.new(commits, & &1.hash)
        |> then(&if(current, do: MapSet.put(&1, current), else: &1))

      explained = MapSet.new(rows, & &1.hash)

      acts =
        Enum.map(rows, fn r ->
          commit = committed(commits, r.hash, r.at)

          %{
            version: r.hash,
            act: r.act,
            at: r.at,
            actor: if(r.actor_kind, do: %{kind: r.actor_kind, id: r.actor_id}),
            note: r.note,
            bytes: r.bytes,
            commit: commit && commit.commit,
            committed_at: commit && commit.at,
            current: r.hash == current,
            restorable: MapSet.member?(held, r.hash)
          }
        end)

      unexplained =
        for c <- commits, not MapSet.member?(explained, c.hash) do
          %{
            version: c.hash,
            act: "committed",
            at: c.at,
            actor: nil,
            note: c.subject,
            bytes: c.bytes,
            commit: c.commit,
            committed_at: c.at,
            current: c.hash == current,
            restorable: true
          }
        end

      {:ok,
       %{
         path: path,
         current: current,
         versions: Enum.sort_by(acts ++ unexplained, & &1.at, {:desc, DateTime})
       }}
    end
  end

  @doc "The words of one version of a path, by its hash: the file now, else the commit that holds them."
  def content(resident_id, path, hash) when is_binary(hash) do
    with {:ok, path} <- path(resident_id, path) do
      if current(resident_id, path) == hash,
        do: read_current(resident_id, path),
        else: from_history(resident_id, path, hash)
    end
  end

  def content(_resident_id, _path, _hash),
    do: {:error, Error.new(:seshat_no_such_version, :seshat_versions_content_no_hash)}

  @doc """
  The line diff from version `from` to version `to` of a path (`to`
  nil: the file now): runs of equal, deleted and inserted lines in
  order, with the counts.
  """
  def diff(resident_id, path, from, to) do
    with {:ok, path} <- path(resident_id, path),
         {:ok, old} <- content(resident_id, path, from),
         {:ok, new} <- to_content(resident_id, path, to) do
      runs =
        old
        |> lines()
        |> List.myers_difference(lines(new))
        |> Enum.map(fn {op, ls} -> %{op: op(op), lines: ls} end)

      {:ok,
       %{
         path: path,
         from: from,
         to: Documents.hash(new),
         added: count(runs, "ins"),
         removed: count(runs, "del"),
         runs: runs
       }}
    end
  end

  @doc """
  Restores a version: the write the normal path makes, with a note
  saying which version it restores. `{:ok, %{path, version, written}}`
  for a write, `{:ok, %{path, version, proposed: ref}}` for an identity
  file whose write is a proposal.
  """
  def restore(resident_id, path, hash, note, %Actor{} = actor) do
    with {:ok, path} <- path(resident_id, path),
         {:ok, words} <- content(resident_id, path, hash) do
      said = restore_note(hash, note)

      if identity?(path),
        do: restore_identity(resident_id, path, hash, words, said, actor),
        else: restore_document(resident_id, path, hash, words, said, actor)
    end
  end

  defp restore_document(resident_id, path, hash, words, said, actor) do
    case Leases.write(resident_id, path, words, actor, note: said) do
      {:ok, written} -> {:ok, %{path: path, version: hash, written: written}}
      other -> other
    end
  end

  # The Files screen's path exactly (`OneiroiWeb.FileController.write/2`):
  # the write first, and the proposal only where the write answers that
  # an edit after first contact is one.
  defp restore_identity(resident_id, file, hash, words, said, actor) do
    case AgathosDaimon.write_file(resident_id, file, words, %{origin: "authored"}, actor) do
      :ok ->
        {:ok, %{path: file, version: hash, written: %{path: file, changed: true}}}

      {:error, %{kind: :agathos_daimon_propose_instead}} ->
        with {:ok, ref} <- AgathosDaimon.propose_edit(resident_id, file, words, said, actor),
             do: {:ok, %{path: file, version: hash, proposed: ref}}

      other ->
        other
    end
  end

  defp restore_note(hash, note) do
    base = "Restored the version #{String.slice(hash, 0, 12)}"

    case note do
      n when is_binary(n) ->
        if String.trim(n) == "", do: base, else: base <> ": " <> String.trim(n)

      _none ->
        base
    end
  end

  # ---- the repository's side ----

  # The commits that changed the path, each with the hash of the words
  # it left there; a commit that removed the path holds no version.
  defp commits(resident_id, path) do
    with {:ok, history} <-
           SimaQian.repository_history(resident_id, path, Config.fetch!(:seshat, :versions_limit)) do
      {:ok,
       history
       |> Enum.filter(& &1.blob)
       |> Enum.flat_map(fn c ->
         case SimaQian.repository_blob(resident_id, c.blob) do
           {:ok, words} ->
             [
               %{
                 commit: c.commit,
                 at: instant(c.at),
                 subject: c.subject,
                 blob: c.blob,
                 hash: Documents.hash(words),
                 bytes: byte_size(words)
               }
             ]

           {:error, _unreadable} ->
             []
         end
       end)}
    end
  end

  defp from_history(resident_id, path, hash) do
    with {:ok, history} <-
           SimaQian.repository_history(resident_id, path, Config.fetch!(:seshat, :versions_limit)) do
      history
      |> Enum.filter(& &1.blob)
      |> Enum.uniq_by(& &1.blob)
      |> Enum.find_value(&holding(resident_id, &1.blob, hash))
      |> Kernel.||(
        {:error, Error.new(:seshat_no_such_version, :seshat_versions_not_held, version: hash)}
      )
    end
  end

  # The blob's words when they are the version's, else nothing.
  defp holding(resident_id, blob, hash) do
    with {:ok, words} <- SimaQian.repository_blob(resident_id, blob),
         true <- Documents.hash(words) == hash do
      {:ok, words}
    else
      _other -> nil
    end
  end

  # The commit that first holds a version's words at or after its act,
  # else the latest that holds them at all (the same words written again).
  defp committed(commits, hash, at) do
    holding = Enum.filter(commits, &(&1.hash == hash))

    holding
    |> Enum.filter(&(DateTime.compare(&1.at, at) != :lt))
    |> List.last()
    |> Kernel.||(List.first(holding))
  end

  defp current(resident_id, path) do
    case read_current(resident_id, path) do
      {:ok, words} -> Documents.hash(words)
      _none -> nil
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_current(resident_id, path) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      case File.read(Path.join(dir, path)) do
        {:ok, words} -> {:ok, words}
        {:error, _absent} -> :none
      end
    end
  end

  defp to_content(resident_id, path, nil) do
    case read_current(resident_id, path) do
      {:ok, words} ->
        {:ok, words}

      _none ->
        {:error, Error.new(:seshat_no_such_version, :seshat_versions_diff_no_current, path: path)}
    end
  end

  defp to_content(resident_id, path, hash), do: content(resident_id, path, hash)

  # ---- helpers ----

  # A library path as the registry normalizes it, or an identity file by
  # its name (spec §6.2), which the registry reserves and the repository
  # holds at its root.
  defp path(resident_id, path) when is_binary(path) do
    if identity?(path), do: {:ok, path}, else: Kinds.normalize(resident_id, path)
  end

  defp path(_resident_id, _path),
    do: {:error, Error.new(:seshat_path_invalid, :seshat_versions_path_missing)}

  defp identity?(path), do: path in AgathosDaimon.identity_files()

  defp instant(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> DateTime.shift_zone!(at, "Etc/UTC")
      _unreadable -> ~U[1970-01-01 00:00:00Z]
    end
  end

  defp lines(words), do: String.split(words, "\n")

  defp op(:eq), do: "eq"
  defp op(:del), do: "del"
  defp op(:ins), do: "ins"

  defp count(runs, op),
    do: runs |> Enum.filter(&(&1.op == op)) |> Enum.map(&length(&1.lines)) |> Enum.sum()
end
