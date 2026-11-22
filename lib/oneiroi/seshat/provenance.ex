defmodule Oneiroi.Seshat.Provenance do
  @moduledoc """
  A file's words at a commit and the turn that wrote them (seshat#100;
  kumbukumbu#83): what a delivery of the file is decided against. The
  version is found by the words' SHA-256 among the path's written
  versions, so the words delivered are the words the provenance speaks
  for; a version written before provenance was kept, adopted, moved or
  written by no turn has none, and its delivery is unproven.
  """

  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian.Repos

  @doc "`{:ok, %{words, source, ledger, turn_ref}}` for `path` at `commit` (nil: the head), or the refusal."
  def of(resident_id, path, commit) do
    repo = {:resident, resident_id}

    with {:ok, path} <- Kinds.normalize(resident_id, to_string(path)),
         {:ok, sha} <- commit_of(repo, commit, path),
         {:ok, files} <- Repos.snapshot_at(repo, sha),
         words when is_binary(words) <- Repos.at(repo, files, path) || absent(path) do
      version = written(resident_id, path, Documents.hash(words))

      {:ok,
       %{
         words: words,
         source: "#{path}@#{String.slice(sha, 0, 12)}",
         ledger: version && version.ledger,
         turn_ref: version && version.turn_ref,
         classified: classified(resident_id, path)
       }}
    end
  end

  @doc "The kept ledger of the version holding `content` at `path`, or nil: what reading those words adds to a turn (kumbukumbu#84)."
  def ledger_of(resident_id, path, content) when is_binary(content) do
    case written(resident_id, path, Documents.hash(content)) do
      %{ledger: ledger} -> ledger
      nil -> nil
    end
  end

  defp commit_of(_repo, commit, _path) when is_binary(commit), do: {:ok, commit}

  defp commit_of(repo, nil, path) do
    case Repos.head(repo) do
      {:ok, sha} when is_binary(sha) -> {:ok, sha}
      _none -> absent(path)
    end
  end

  # Its author's classification (seshat#102), `%{person, domain}` with
  # `domain` nil for the common room, or nil when never classified.
  defp classified(resident_id, path) do
    case Scope.resident(resident_id, fn -> Store.document(path) end) do
      %{classified_at: %DateTime{}} = d -> %{person: d.class_person, domain: d.class_domain}
      _unclassified -> nil
    end
  end

  # The written version, its ledger the derived labels' where they were
  # derived again (kumbukumbu#101): the birth a delivery decides on.
  defp written(resident_id, path, hash) do
    resident_id
    |> Scope.resident(fn -> Store.versions(path) end)
    |> Enum.find(&(&1.act == "written" and &1.hash == hash))
    |> derived(resident_id)
  end

  defp derived(nil, _resident_id), do: nil

  defp derived(version, resident_id) do
    id = "#{version.path}@#{version.hash}"

    case Oneiroi.Kumbukumbu.derived_labels(resident_id, "file", [id]) do
      %{^id => labels} -> %{version | ledger: Oneiroi.Kumbukumbu.labels_ledger(labels)}
      _none -> version
    end
  end

  defp absent(path),
    do: {:error, Error.new(:seshat_no_such_document, :seshat_provenance_absent, path: path)}
end
