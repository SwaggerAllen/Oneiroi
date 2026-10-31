defmodule Oneiroi.SimaQian.DryRun do
  @moduledoc """
  The import rehearsed on a throwaway store (sima-qian #18): a local
  checkout imported exactly as `POST /v1/residents/import` imports it,
  then backed up once to a local bare remote, and a report of what
  happened. No turn is taken, so nobody is at turn one (spec §12, P40);
  the store the task runs against is refused if it already holds a
  resident, and the provider must be the in-memory one, so the rehearsal
  makes no model call (`mix oneiroi.import.dry_run`).

  The report names files and counts them and never quotes one: it is
  written to a CI log, and the repository it describes is a person's.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.David
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Import

  # The prefix's own estimate, four bytes a token (brain #27).
  @bytes_per_token 4

  @type report :: map()

  @doc """
  Imports the repository checked out at `source` (a directory with a
  `main` branch) as `attrs` under `witness_account_id`, then backs it up
  to a bare remote under the temp dir. `{:ok, report}` when both ran;
  `{:error, report}` with the step that failed in `:failed` otherwise.
  """
  @spec run(Path.t(), map(), String.t(), Actor.t()) :: {:ok, report()} | {:error, report()}
  # Every path here is the task's argument or a directory this module
  # made under the temp dir; nothing reaches it from a request.
  # sobelow_skip ["Traversal.FileModule"]
  def run(source, attrs, witness_account_id, %Actor{} = actor) do
    source = Path.expand(source)
    report = %{source: Path.basename(source), shape: shape(source)}

    case timed(fn -> Import.run("file://" <> source, attrs, witness_account_id, actor) end) do
      {{:ok, result}, ms} ->
        report
        |> Map.merge(%{import: result, import_ms: ms, soul_lines: soul_lines(result.id)})
        |> backup(actor)
        |> accounted()

      {{:error, reason}, ms} ->
        {:error, Map.merge(report, %{failed: :import, reason: inspect(reason), import_ms: ms})}
    end
  end

  # The repository as the import will meet it, read before it runs:
  # each kind's folder by files and bytes (the bytes are what the index
  # will embed), and, when the source is not an Oneiroi export, what it
  # keeps under `honcho/`, which nothing here reads, and under
  # `records/` unless those are David's, which the import translates
  # (sima-qian #19) and names file by file where it does not.
  defp shape(source) do
    folders =
      for folder <- library().folders() do
        files = files(Path.join(source, folder))
        %{folder: folder, files: length(files), bytes: bytes(files)}
      end

    export? = File.dir?(Path.join([source, "records", "events"]))
    david? = David.present?(source)

    foreign =
      cond do
        export? -> []
        david? -> ["honcho"]
        true -> ["records", "honcho"]
      end
      |> Enum.flat_map(fn dir ->
        source |> Path.join(dir) |> files() |> Enum.map(&Path.relative_to(&1, source))
      end)

    %{folders: folders, oneiroi_export: export?, david: david?, unread: Enum.sort(foreign)}
  end

  # The bare remote is a directory this function makes under the temp
  # dir and removes again; no path in it comes from a request.
  # sobelow_skip ["Traversal.FileModule"]
  defp backup(report, actor) do
    id = report.import.id
    bare = Path.join(System.tmp_dir!(), "oneiroi-dry-run-#{System.unique_integer([:positive])}")

    try do
      :ok = Git.init_bare(bare)
      :ok = Backup.set_remote(id, bare, nil, actor)

      case timed(fn -> Backup.run(id, actor) end) do
        {{:ok, backup}, ms} ->
          {:ok, Map.merge(report, %{backup: backup, backup_ms: ms})}

        {{:error, reason}, ms} ->
          {:error, Map.merge(report, %{failed: :backup, reason: inspect(reason), backup_ms: ms})}
      end
    after
      File.rm_rf(bare)
    end
  end

  # A file nothing accounts for fails the rehearsal (sima-qian #22): the
  # rehearsal of 2026-10-31 passed with one of Lily's files neither
  # adopted nor named, and only the folder count disagreeing with the
  # adopted count said anything.
  @doc false
  # Public for its test: no real repository reaches it while every case
  # has a rule, which is what it guards.
  def accounted({:ok, %{import: %{unaccounted: [_ | _]}} = r}),
    do: {:error, Map.put(r, :failed, :accounting)}

  def accounted(other), do: other

  @doc "The report as Markdown: names and counts, never a file's contents."
  @spec markdown({:ok | :error, report()}) :: String.t()
  def markdown({outcome, r}) do
    verdict =
      case outcome do
        :ok -> "IMPORT DRY RUN: ok"
        :error -> "IMPORT DRY RUN: FAILED at #{r.failed}"
      end

    [
      "# #{verdict}",
      "",
      "Source checkout `#{r.source}`; no turn was taken and no model was called.",
      "",
      section_import(r),
      section_folders(r.shape),
      section_translated(r),
      section_reconciled(r),
      section_not_transferred(r),
      section_unaccounted(r),
      section_unread(r.shape),
      section_backup(r),
      if(Map.has_key?(r, :reason), do: "## Failure\n\n```\n#{r.reason}\n```\n", else: ""),
      "# #{verdict}"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("\n\n", &String.trim_trailing/1)
  end

  defp section_import(%{import: i} = r) do
    """
    ## The import (#{r.import_ms} ms)

    | | |
    | --- | --- |
    | Replayed events | #{i.events} |
    | Identity files seeded | #{list(i.seeded)} |
    | Proposed instead | #{list(i.proposed)} |
    | Soul lines minted | #{r.soul_lines} |
    | Documents adopted | #{i.adopted} |
    | Index ran | #{i.indexed} |
    """
  end

  defp section_import(_r), do: ""

  defp section_folders(shape) do
    rows =
      Enum.map_join(shape.folders, "\n", fn f ->
        "| `#{f.folder}` | #{f.files} | #{f.bytes} | #{div(f.bytes, @bytes_per_token)} |"
      end)

    total = shape.folders |> Enum.map(& &1.bytes) |> Enum.sum()

    """
    ## The library's folders

    | Folder | Files | Bytes | Tokens to embed, estimated at #{@bytes_per_token} bytes each |
    | --- | --- | --- | --- |
    #{rows}

    About #{div(total, @bytes_per_token)} tokens go through the embedding model on a real import, inside the import's own request.
    """
  end

  # The kinds in the order the orientation names them (brain #38).
  @translated ~w(sessions messages bookmarks tags positions disputes predictions nights notes)

  defp section_translated(%{import: %{translated: %{source: source, counts: counts}}}) do
    rows = Enum.map_join(@translated, "\n", &"| #{&1} | #{Map.get(counts, &1, 0)} |")

    """
    ## Translated from #{source}'s records

    | Kind | Made into this platform's own |
    | --- | --- |
    #{rows}
    """
  end

  defp section_translated(_r), do: ""

  defp section_not_transferred(%{import: i}) do
    rows =
      case i.not_transferred do
        [] -> "- none"
        names -> Enum.map_join(names, "\n", &left_row(&1, Map.get(i.reasons, &1)))
      end

    "## Not transferred, as she will be told on waking\n\n#{rows}\n"
  end

  defp section_not_transferred(_r), do: ""

  defp left_row(name, nil), do: "- `#{name}`"
  defp left_row(name, reason), do: "- `#{name}`: #{reason}"

  # The folders' files against what became of them, so the counts are
  # seen to add up rather than left for a reader to subtract.
  defp section_reconciled(%{import: i, shape: shape}) do
    on_disk = shape.folders |> Enum.map(& &1.files) |> Enum.sum()
    folders = Enum.map(shape.folders, & &1.folder)

    left =
      Enum.count(i.not_transferred, fn name ->
        String.contains?(name, "/") and hd(String.split(name, "/")) in folders
      end)

    """
    ## Every file under the folders, accounted

    #{on_disk} on disk: #{i.adopted} adopted, #{left} left behind with a reason (#{length(i.unaccounted)} of them unaccounted).
    """
  end

  defp section_reconciled(_r), do: ""

  defp section_unaccounted(%{import: %{unaccounted: [_ | _] = paths}}) do
    """
    ## Unaccounted

    The library's adoption neither took nor refused these, and no rule of the import's explains them; she is told they were left behind, and the rehearsal fails until a rule does:

    #{bullets(paths)}
    """
  end

  defp section_unaccounted(_r), do: ""

  defp section_unread(%{oneiroi_export: true}), do: ""

  defp section_unread(%{david: true, unread: unread}) do
    """
    ## Under `honcho/`, read by nothing

    These files come across as files and no record is made from any of them; Honcho is built anew from the conversations here:

    #{bullets(unread)}
    """
  end

  defp section_unread(%{unread: unread}) do
    """
    ## Under `records/` and `honcho/`, read by nothing

    This repository is not an Oneiroi export, so these files come across as files and no record is made from any of them:

    #{bullets(unread)}
    """
  end

  defp section_backup(%{backup: b} = r) do
    commits =
      Enum.map_join(b.commits, ", ", fn {class, sha} ->
        "#{class} #{sha || "(nothing to commit)"}"
      end)

    """
    ## The first backup (#{r.backup_ms} ms)

    Exported through sequence #{b.through}; commits: #{commits}.
    """
  end

  defp section_backup(_r), do: ""

  defp list([]), do: "none"
  defp list(names), do: Enum.map_join(names, ", ", &"`#{&1}`")

  defp bullets([]), do: "- none"
  defp bullets(names), do: Enum.map_join(names, "\n", &"- `#{&1}`")

  defp soul_lines(id), do: id |> AgathosDaimon.soul_lines() |> length()

  defp timed(fun) do
    {us, value} = :timer.tc(fun)
    {value, div(us, 1000)}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp files(dir) do
    if File.dir?(dir),
      do: Path.wildcard(Path.join(dir, "**/*"), match_dot: true) |> Enum.filter(&File.regular?/1),
      else: []
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp bytes(files), do: files |> Enum.map(&File.stat!(&1).size) |> Enum.sum()

  defp library, do: Config.fetch!(:sima_qian, :library)
end
