defmodule Oneiroi.SimaQian.Backup do
  @moduledoc """
  The nightly unit (spec §6.10): export, root, commit by class with the
  trailers, push, and record both facts on the resident's stream.

  Commits by class as David's backup does: the soul alone, writing and
  research apart, machine state together; anything else uncommitted fails
  the run after the rest has landed, so a stray write is loud and the
  backup is still taken. In P0 the only class with files is the machine
  one, `records/`; the table is here so the others arrive as rows.
  """

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Merkle

  @classes [
    # The soul alone (David's rule), and the identity files with it: they
    # are one self, given and proposed together (spec §6.2).
    {"soul", ["SOUL.md", "IDENTITY.md", "USER.md", "GOALS.md", "LINKS.md", "honcho/"]},
    # `posts/` is a library folder (Seshat's kinds) and was in no class, so
    # the first resident to publish one would have failed every backup on
    # the stray check.
    {"writing", ["writing/", "research/", "posts/"]},
    {"machine",
     ["records/", "memory/", "feeds/", "mail/", "correspondence/", "design/", "wiki/", "journal/"]}
  ]

  def set_remote(resident_id, url, token, %Actor{} = actor) when is_binary(url) do
    ciphertext = (Secret.reveal(token) || "") |> Vault.encrypt() |> Base.encode64()

    command = %Commands.SetRecordsRemote{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      url: url,
      token_ciphertext: ciphertext
    }

    with {:ok, _} <- Router.dispatch_sited(command), do: :ok
  end

  def run(resident_id, %Actor{} = actor) do
    dir = dir(resident_id)
    row = Scope.resident(resident_id, fn -> Store.get(resident_id) end)

    with :ok <- fresh_if_foreign(resident_id, dir, row),
         :ok <- Git.ensure_repo(dir),
         {:ok, export} <- Export.write(resident_id, dir),
         {:ok, _} <- record_export(resident_id, export, actor),
         # The letters the export carried for the first time get their
         # receipt (agathos-daimon #28): the words left the house.
         :ok <- Oneiroi.AgathosDaimon.letters_exported(resident_id, Export.cutoff(), actor),
         root = Merkle.root(Path.join(dir, "records")),
         {:ok, commits} <- commit_classes(dir, export.through, root),
         :ok <- push(dir, row),
         {:ok, _} <- record_backup(resident_id, export.through, root, commits, actor) do
      :telemetry.execute([:oneiroi, :sima_qian, :backup], %{through: export.through}, %{
        resident_id: resident_id
      })

      # The card comes from git, always (spec §6.9): set after the soul
      # commit; a bridge not yet provisioned, or a Honcho that is down,
      # is the bridge's to record and never the backup's to fail on.
      if Enum.any?(commits, &match?({"soul", sha} when is_binary(sha), &1)),
        do: Oneiroi.Proteus.set_card(resident_id, "commit", actor)

      case Git.stray(dir, Enum.flat_map(@classes, &elem(&1, 1))) do
        [] ->
          {:ok, %{through: export.through, root: root, commits: commits}}

        stray ->
          {:error, Error.new(:sima_qian_stray_files, :sima_qian_backup_stray, paths: stray)}
      end
    end
  end

  def attest(resident_id, %Actor{} = actor) do
    dir = dir(resident_id)
    row = Scope.resident(resident_id, fn -> Store.get(resident_id) end)

    cond do
      is_nil(row) or is_nil(row.last_backup_root) ->
        {:ok, :none}

      Merkle.root(Path.join(dir, "records")) == row.last_backup_root ->
        {:ok, :held}

      true ->
        actual = Merkle.root(Path.join(dir, "records"))

        command = %Commands.RecordMismatch{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          expected_root: row.last_backup_root,
          actual_root: actual,
          commit: row.last_backup_commit
        }

        with {:ok, _} <- Router.dispatch_sited(command), do: {:ok, :mismatch}
    end
  end

  @doc """
  Makes `dir` hold only what the platform holds, under a history of its
  own: the source repository's `.git` goes, each name the import left
  behind goes, and so does anything else outside the backup's classes
  (a translated source such as a seedbed, now events). The source
  repository still holds all of it.

  Before this, an import kept the clone whole: Lily's records repository
  carried her original history and every file the import had named as
  not transferred, and her first backup (2026-11-01) was refused by
  GitHub for pushing her CI workflow, `.github/workflows/...`, a file
  the import had listed as left behind. The author chose a fresh history
  over keeping hers: the backup holds what the platform says it holds,
  and the provenance is the import's event (source, attestation, root).
  """
  @spec start_fresh(Path.t(), [String.t()]) :: :ok | {:error, Error.t()}
  # Every path is under the records root, made from names the import's
  # own accounting produced; `Path.safe_relative/1` refuses one that
  # would climb out.
  # sobelow_skip ["Traversal.FileModule"]
  def start_fresh(dir, left_behind) do
    File.rm_rf!(Path.join(dir, ".git"))

    for name <- left_behind, {:ok, safe} <- [Path.safe_relative(name)] do
      File.rm_rf!(Path.join(dir, safe))
    end

    held = Enum.flat_map(@classes, &elem(&1, 1))

    for path <- files(dir), not Enum.any?(held, &String.starts_with?(path, &1)) do
      File.rm!(Path.join(dir, path))
    end

    Git.ensure_repo(dir)
  end

  # Once, for a resident imported before `start_fresh/2` ran at import:
  # never backed up, and a history that did not begin as ours. The root
  # commit decides, not the head: Lily's first backup committed on top of
  # her own history and failed at the push, so her head carries our
  # trailer and her root does not. A history that began as ours is never
  # touched, and nothing is reset after the first backup lands.
  defp fresh_if_foreign(resident_id, dir, %{last_backup_commit: nil, import_source: source} = row)
       when is_binary(source) do
    # Its own `.git` first: git walks up from a directory without one, and
    # a records root inside another repository would read that one's head.
    if File.dir?(Path.join(dir, ".git")) and Git.head?(dir) and
         not Map.has_key?(Git.root_trailers(dir), "Oneiroi-Sequence") do
      Logger.info("records history started fresh for imported resident #{resident_id}")
      left = Enum.uniq(Map.keys(row.import_reasons || %{}) ++ (row.import_not_transferred || []))
      start_fresh(dir, left)
    else
      :ok
    end
  end

  defp fresh_if_foreign(_resident_id, _dir, _row), do: :ok

  # Every file under `dir`, hidden ones included, but its `.git`.
  # sobelow_skip ["Traversal.FileModule"]
  defp files(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.reject(&(&1 == ".git" or String.starts_with?(&1, ".git/")))
  end

  @doc "Every resident with a remote, for the nightly jobs; platform scope by name."
  def residents_with_remote, do: Scope.platform(fn -> Store.with_remote() end)

  @doc "The resident's working repository."
  def dir(resident_id), do: Path.join(Config.fetch!(:sima_qian, :root), resident_id)

  @doc "The working repository, made one if it is not yet: the library writes its files there between backups."
  def repository_dir(resident_id) do
    dir = dir(resident_id)
    with :ok <- Git.ensure_repo(dir), do: {:ok, dir}
  end

  defp record_export(resident_id, export, actor) do
    Router.dispatch_sited(%Commands.RecordExport{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      through: export.through,
      files: export.files
    })
  end

  defp commit_classes(dir, through, root) do
    message = fn class ->
      "Records: #{class} through sequence #{through}\n\nOneiroi-Sequence: #{through}\nOneiroi-Root: #{root}\n"
    end

    Enum.reduce_while(@classes, {:ok, []}, fn {class, paths}, {:ok, acc} ->
      case commit_class(
             dir,
             Enum.filter(paths, &File.exists?(Path.join(dir, &1))),
             message.(class)
           ) do
        {:ok, :nothing} -> {:cont, {:ok, acc}}
        {:ok, sha} -> {:cont, {:ok, acc ++ [{class, sha}]}}
        {:error, _git} = failed -> {:halt, failed}
      end
    end)
  end

  defp commit_class(_dir, [], _message), do: {:ok, :nothing}
  defp commit_class(dir, present, message), do: Git.commit(dir, present, message)

  defp push(_dir, %{remote_url: nil}), do: :ok
  defp push(_dir, nil), do: :ok

  defp push(dir, %{remote_url: url, remote_token: token}) do
    remote =
      case {token && Vault.decrypt(token), url} do
        {{:ok, ""}, _} -> url
        {{:ok, plain}, "https://github.com/" <> _} -> Git.github_url(url, plain)
        _ -> url
      end

    Git.push(dir, remote)
  end

  defp record_backup(_resident_id, _through, _root, [], _actor), do: {:ok, []}

  defp record_backup(resident_id, through, root, commits, actor) do
    {_class, sha} = List.last(commits)

    Router.dispatch_sited(%Commands.RecordBackup{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      sequence: through,
      root: root,
      commit: sha
    })
  end
end
