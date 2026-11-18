defmodule Oneiroi.Seshat.Published do
  @moduledoc """
  Publishing (seshat#85; design/workspaces.md §4, the witness's answers
  of 2026-11-17): a draft of a file made public to the household, one
  commit at a time, recorded in the repository the file is in.

  **Per commit, explicit.** What is public is a commit of a file, never
  the file: a later draft is public only when it too is published, so
  nothing drifts public by default. A draft is published only when it
  comes after the one public already; an earlier draft goes back by a
  restore, a new commit with its words (seshat#54), published in turn.
  History is only added to: Gitea refuses a force-push (sima-qian#64),
  so every citation of a published commit holds.

  **Where it is recorded.** `DocumentPublished` on the library stream of
  the repository's resident, and `PUBLISHED.md` at that repository's
  root, rendered on every publish, one draft a line: the record is in
  the source repository, whoever published (the witness's own files in
  her repository record there, not in an account of his).

  **Who publishes.** The resident her own files; a witness his own,
  in his name-folder, `human/<name>/` (seshat#81).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Gaia
  alias Oneiroi.Seshat.Commands
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Router
  alias Oneiroi.SimaQian.Repos

  @file_name "PUBLISHED.md"
  @drafts 200

  @doc "The record's file name, at the repository's root."
  def file_name, do: @file_name

  @doc """
  Publishes `path` at `commit` (a full sha or a prefix of one) in the
  resident's repository, with `note`; answers the draft published.
  """
  def publish(resident_id, path, commit, note, %Actor{} = actor) do
    repo = {:resident, resident_id}

    with {:ok, path} <- Kinds.normalize(resident_id, to_string(path)),
         :ok <- may_publish(resident_id, path, actor),
         {:ok, drafts} <- drafts(repo, path),
         {:ok, sha} <- draft(drafts, commit, path),
         :ok <- after_public(drafts, sha, latest(resident_id, path), path),
         note = noted(note),
         {:ok, _} <- dispatch(resident_id, path, sha, note, actor),
         {:ok, _} <- record(repo, path, sha, note, actor) do
      {:ok, %{path: path, commit: sha}}
    end
  end

  @doc """
  Every draft published in the resident's repository, oldest first:
  `%{path, commit, at, by, note}`, read from `PUBLISHED.md`.
  """
  def all(resident_id) do
    case Repos.text({:resident, resident_id}, @file_name) do
      nil -> []
      text -> parse(text)
    end
  end

  @doc "The commit of `path` published last, or nil."
  def latest(resident_id, path) do
    resident_id
    |> all()
    |> Enum.filter(&(&1.path == path))
    |> List.last()
    |> then(&(&1 && &1.commit))
  end

  @doc "Whether `path` at `commit` (a full sha or a prefix) is published."
  def published?(resident_id, path, commit) when is_binary(commit) do
    Enum.any?(all(resident_id), &(&1.path == path and String.starts_with?(&1.commit, commit)))
  end

  def published?(_resident_id, _path, _commit), do: false

  # ---- who ----

  defp may_publish(resident_id, path, %Actor{kind: :resident, id: resident_id}) do
    if Kinds.kind_of(resident_id, path).kind == "human",
      do:
        {:error,
         Error.new(:seshat_publish_not_yours, :seshat_publish_not_yours_human, path: path)},
      else: :ok
  end

  defp may_publish(resident_id, path, %Actor{kind: :witness, id: id}) do
    folder = Gaia.witness_folder(id)

    if resident_id in Gaia.witnessed_residents(id) and is_binary(folder) and
         String.starts_with?(path, "human/#{folder}/"),
       do: :ok,
       else:
         {:error,
          Error.new(:seshat_publish_not_yours, :seshat_publish_not_yours_witness, path: path)}
  end

  defp may_publish(_resident_id, path, _actor),
    do:
      {:error, Error.new(:seshat_publish_not_yours, :seshat_publish_not_yours_other, path: path)}

  # ---- which draft ----

  # The commits that changed the file, newest first: its drafts.
  defp drafts(repo, path) do
    case Repos.history(repo, path, @drafts) do
      {:ok, [_ | _] = drafts} ->
        {:ok, Enum.map(drafts, & &1.commit)}

      _none ->
        {:error, Error.new(:seshat_no_such_document, :seshat_publish_no_drafts, path: path)}
    end
  end

  defp draft(drafts, commit, path) when is_binary(commit) and byte_size(commit) >= 7 do
    case Enum.filter(drafts, &String.starts_with?(&1, String.downcase(commit))) do
      [sha] ->
        {:ok, sha}

      _none ->
        {:error,
         Error.new(:seshat_publish_no_such_draft, :seshat_publish_draft_absent,
           path: path,
           commit: commit
         )}
    end
  end

  defp draft([latest | _], nil, _path), do: {:ok, latest}

  defp draft(_drafts, commit, path),
    do:
      {:error,
       Error.new(:seshat_publish_no_such_draft, :seshat_publish_draft_short,
         path: path,
         commit: to_string(commit)
       )}

  # Only a draft after the one public (the witness: "publish this draft"
  # on a later one, "already published" on that one or an earlier).
  defp after_public(_drafts, _sha, nil, _path), do: :ok

  defp after_public(drafts, sha, public, path) do
    if index(drafts, sha) < index(drafts, public),
      do: :ok,
      else:
        {:error,
         Error.new(:seshat_publish_already, :seshat_publish_not_after,
           path: path,
           published: String.slice(public, 0, 12)
         )}
  end

  # Newest first, so a smaller index is a later draft; a public commit
  # past the window counts as the oldest.
  defp index(drafts, sha), do: Enum.find_index(drafts, &(&1 == sha)) || length(drafts)

  defp noted(note) do
    case note |> to_string() |> String.trim() do
      "" -> "published"
      words -> words
    end
  end

  # ---- the record ----

  defp dispatch(resident_id, path, sha, note, actor) do
    command = %Commands.PublishDocument{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      path: path,
      commit: sha,
      note: note
    }

    case Router.dispatch(command) do
      {:ok, _} = ok ->
        ok

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_publish_dispatch_failed, reason)}
    end
  end

  defp record(repo, path, sha, note, actor) do
    {current, blob} =
      case Repos.read(repo, @file_name) do
        {:ok, text, blob} -> {text, blob}
        _absent -> {nil, nil}
      end

    line =
      "- #{path} @ #{sha} · #{DateTime.to_iso8601(Clock.now())} · #{who(actor)} · #{one_line(note)}"

    Repos.write(
      repo,
      [{:put, @file_name, (current || header()) <> line <> "\n", blob}],
      "Published: #{path} @ #{String.slice(sha, 0, 12)}",
      Repos.author(actor)
    )
  end

  defp header,
    do: """
    # PUBLISHED

    The drafts public to the household (seshat#85), oldest first, one a line: the file, the commit, when, by whom, and why. A draft is public at its commit only; a later one is public when it too is published. Written by the platform on every publish.

    """

  defp who(%Actor{kind: kind, id: id}), do: "#{kind}:#{id}"

  defp one_line(text), do: text |> String.split() |> Enum.join(" ")

  @line ~r/^- (\S.*?) @ ([0-9a-f]{7,64}) · (\S+) · (\S+) · (.*)$/

  defp parse(text) do
    for line <- String.split(text, "\n"),
        [_, path, commit, at, by, note] <- [Regex.run(@line, line)],
        do: %{path: path, commit: commit, at: at, by: by, note: note}
  end
end
