defmodule Oneiroi.SimaQian.Backup do
  @moduledoc """
  The nightly unit (spec §6.10): export, root, commit by class with the
  trailers, push, and record both facts on the resident's stream.

  The export is built in a directory of the run's own and committed
  through the repositories' port (sima-qian#57), class by class as
  David's backup does (the soul alone, machine state together), each
  class only what changed; what a run's export no longer writes is
  removed. The library's files are not the backup's: each was committed
  when it was written.

  Before the commit, Honcho's memory of the resident is written under
  `honcho/` (sima-qian#42), in the soul class; a Honcho that cannot
  answer leaves the last of it in place and is the run's error after
  the rest has landed.
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
  alias Oneiroi.SimaQian.HonchoMemory
  alias Oneiroi.SimaQian.Household
  alias Oneiroi.SimaQian.Merkle
  alias Oneiroi.SimaQian.Repos

  @classes [
    # The soul alone (David's rule), and the identity files with it: they
    # are one self, given and proposed together (spec §6.2).
    {"soul", ["SOUL.md", "IDENTITY.md", "USER.md", "GOALS.md", "LINKS.md", "honcho/"]},
    # The state store (agathos-daimon#32): the resident's present, which
    # can change every turn. A class of its own, so a changed line never
    # makes a soul commit and the Honcho card it sets.
    {"state", ["STATE.md"]},
    # `posts/` is a library folder (Seshat's kinds) and was in no class, so
    # the first resident to publish one would have failed every backup on
    # the stray check.
    {"writing", ["writing/", "research/", "posts/", "system/"]},
    # `memory/` holds the originals of the resident's daily memory, a copy
    # of the source at a pinned commit that nothing writes again (seshat
    # #28): machine state by #7's rule, beside the export it sits with
    # (the soul class is the identity files alone, and writing is what
    # the dyad writes through the flow).
    {"machine",
     [
       "records/",
       "memory/",
       "feeds/",
       "mail/",
       "correspondence/",
       "design/",
       "wiki/",
       "journal/",
       "oracle/",
       # Her routes' definitions (xenia#19): rows serialized, as records.
       "routes/"
     ]},
    # The household's repository as it travels with her records
    # (sima-qian#53): a copy, titled by the membership, rewritten whole
    # each run; a class of its own, so a sibling's post never rides in a
    # commit of hers.
    {"household", ["household/"]}
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

  # The staging directory is this run's own under the temp dir.
  # sobelow_skip ["Traversal.FileModule"]
  def run(resident_id, %Actor{} = actor) do
    row = Scope.resident(resident_id, fn -> Store.get(resident_id) end)
    repo = {:resident, resident_id}
    staging = staging_dir(resident_id)

    try do
      with :ok <- fresh_if_foreign(resident_id, dir(resident_id), row),
           {:ok, export} <- Export.write(resident_id, staging),
           # Honcho's memory of her, before the commit that carries it
           # (sima-qian#42); a failure is returned after the rest lands.
           honcho = HonchoMemory.write(resident_id, staging, export.private),
           export = %{export | files: export.files ++ honcho_files(honcho)},
           {:ok, _} <- record_export(resident_id, export, actor),
           # The letters the export carried for the first time get their
           # receipt (agathos-daimon#28): the words left the house.
           :ok <- Oneiroi.AgathosDaimon.letters_exported(resident_id, Export.cutoff(), actor),
           root = Merkle.root(Path.join(staging, "records")),
           :ok <- Household.travel(resident_id, staging),
           {:ok, commits} <- commit_staged(repo, staging, owned(honcho), export.through, root),
           :ok <- push(repo, row),
           {:ok, _} <- record_backup(resident_id, export.through, root, commits, actor) do
        :telemetry.execute([:oneiroi, :sima_qian, :backup], %{through: export.through}, %{
          resident_id: resident_id
        })

        # The card comes from git, always (spec §6.9): set after the soul
        # commit; a bridge not yet provisioned, or a Honcho that is down,
        # is the bridge's to record and never the backup's to fail on.
        if Enum.any?(commits, &match?({"soul", sha} when is_binary(sha), &1)),
          do: Oneiroi.Proteus.set_card(resident_id, "commit", actor)

        case honcho do
          {:ok, _written} -> {:ok, %{through: export.through, root: root, commits: commits}}
          {:error, _unreadable_or_empty} = failed -> failed
        end
      end
    after
      File.rm_rf(staging)
    end
  end

  # The export is built in a directory of its own for the run alone
  # (sima-qian#57): the repository is Gitea's, and this node keeps
  # nothing of it between runs.
  # sobelow_skip ["Traversal.FileModule"]
  defp staging_dir(resident_id) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "oneiroi-export-#{resident_id}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    dir
  end

  # What a run's export rewrites whole, so a file it no longer writes is
  # removed: the records, the identity files and the state, the household's
  # copy when it travelled, and Honcho's files when Honcho answered.
  defp owned(honcho) do
    always = [
      ~r{\Arecords/},
      ~r{\A(SOUL|IDENTITY|USER|GOALS|LINKS|STATE)\.md\z},
      ~r{\Ahoncho/custom-instructions\.md\z}
    ]

    case honcho do
      {:ok, _} ->
        always ++ [~r{\Ahoncho/[^/]+/(card|conclusions)\.md\z}, ~r{\Ahoncho/summaries\.md\z}]

      _failed ->
        always
    end
  end

  def attest(resident_id, %Actor{} = actor) do
    row = Scope.resident(resident_id, fn -> Store.get(resident_id) end)

    with false <- is_nil(row) or is_nil(row.last_backup_root),
         {:ok, actual} <- records_root(resident_id) do
      compare(resident_id, row, actual, actor)
    else
      true -> {:ok, :none}
      other -> other
    end
  end

  defp compare(_resident_id, %{last_backup_root: root}, root, _actor), do: {:ok, :held}

  defp compare(resident_id, row, actual, actor) do
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

  # The Merkle root over the repository's `records/` as it stands
  # (sima-qian#57), its files through the blob cache.
  defp records_root(resident_id) do
    repo = {:resident, resident_id}

    with {:ok, files} <- Repos.snapshot(repo) do
      {:ok,
       files
       |> Repos.under("records")
       |> Enum.map(&{String.replace_prefix(&1, "records/", ""), Repos.at(repo, files, &1)})
       |> Merkle.root_of()}
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

    held = held(dir)

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
    if File.dir?(Path.join(dir, ".git")) and Git.head?(dir) and not ours?(Git.root_trailers(dir)) do
      Logger.info("records history started fresh for imported resident #{resident_id}")
      left = Enum.uniq(Map.keys(row.import_reasons || %{}) ++ (row.import_not_transferred || []))
      start_fresh(dir, left)
    else
      :ok
    end
  end

  defp fresh_if_foreign(_resident_id, _dir, _row), do: :ok

  # A history that began as ours: a backup's first commit, or the
  # import's own (sima-qian#57), never the source's.
  defp ours?(trailers),
    do: Map.has_key?(trailers, "Oneiroi-Sequence") or Map.has_key?(trailers, "Oneiroi-Import")

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

  @doc "Removes the working repository of a resident deleted before their first turn (agathos-daimon#49)."
  def discard(resident_id) do
    {:ok, id} = Ecto.UUID.cast(resident_id)
    File.rm_rf!(dir(id))
    :ok
  end

  @doc "The working repository, made one if it is not yet: the library writes its files there between backups."
  def repository_dir(resident_id) do
    dir = dir(resident_id)
    with :ok <- Git.ensure_repo(dir), do: {:ok, dir}
  end

  defp honcho_files({:ok, paths}), do: paths
  defp honcho_files({:error, _failed}), do: []

  defp record_export(resident_id, export, actor) do
    Router.dispatch_sited(%Commands.RecordExport{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      through: export.through,
      files: export.files
    })
  end

  # The classes as they stand in `dir`: the table's, with the keepsakes
  # at the root (seshat#29) as a class of their own after the soul,
  # since they are named file by file rather than by a folder. Kept
  # apart from the soul, which is the identity files alone (#7), and
  # from writing, which is what the dyad writes through the flow.
  #
  # Then the library's (sima-qian#48): every folder the library keeps
  # that no class above names, her own kinds' among them (seshat#51).
  # The table had been written out by hand, so scratch/, human/,
  # plugins/, external/ and archive/ were strays, and so would every
  # kind of hers be: read from the registry, a kind added is committed.
  defp classes(dir) do
    [soul | rest] = @classes
    named = Enum.flat_map(@classes, &elem(&1, 1))
    library = Enum.reject(library().kept(Path.basename(dir)), &(&1 in named))
    [soul, {"keepsake", keepsakes(dir)} | rest] ++ [{"library", library}]
  end

  defp held(dir), do: dir |> classes() |> Enum.flat_map(&elem(&1, 1))

  # Exact names, not prefixes: the stray check and `start_fresh/2` read a
  # class's paths as prefixes, and a name is its own prefix.
  # sobelow_skip ["Traversal.FileModule"]
  defp keepsakes(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&(library().decided?(&1) and File.regular?(Path.join(dir, &1))))
        |> Enum.sort()

      {:error, _absent} ->
        []
    end
  end

  defp library, do: Config.fetch!(:sima_qian, :library)

  # The staged export committed through the repositories' port
  # (sima-qian#57), class by class with the run's trailers, each class
  # only what changed: a file whose blob is the repository's already is
  # no change, and an owned file the run no longer wrote is removed. The
  # household's copy is owned when it travelled this run.
  defp commit_staged(repo, staging, owned, through, root) do
    message = fn class ->
      "Records: #{class} through sequence #{through}\n\nOneiroi-Sequence: #{through}\nOneiroi-Root: #{root}\n"
    end

    with {:ok, head} <- Repos.snapshot(repo) do
      staged = staged(staging)

      owned =
        if File.dir?(Path.join(staging, "household")), do: [~r{\Ahousehold/} | owned], else: owned

      puts =
        for {path, bytes} <- staged,
            Map.get(head, path) != Repos.Local.sha(bytes),
            do: {:put, path, bytes, :any}

      deletes =
        for path <- Map.keys(head),
            not Map.has_key?(staged, path),
            Enum.any?(owned, &Regex.match?(&1, path)),
            do: {:delete, path, Map.fetch!(head, path)}

      (puts ++ deletes)
      |> Enum.group_by(&class_of(elem(&1, 1)))
      |> Enum.sort_by(fn {class, _} -> Enum.find_index(class_order(), &(&1 == class)) end)
      |> Enum.reduce_while({:ok, []}, &commit_class(repo, message, &1, &2))
    end
  end

  defp commit_class(repo, message, {class, changes}, {:ok, acc}) do
    case Repos.write(repo, changes, message.(class), Repos.platform()) do
      {:ok, :nothing} -> {:cont, {:ok, acc}}
      {:ok, sha} -> {:cont, {:ok, acc ++ [{class, sha}]}}
      {:error, _} = failed -> {:halt, failed}
    end
  end

  defp class_order, do: Enum.map(@classes, &elem(&1, 0)) ++ ["other"]

  defp class_of(path) do
    Enum.find_value(@classes, "other", fn {class, prefixes} ->
      if Enum.any?(prefixes, &String.starts_with?(path, &1)), do: class
    end)
  end

  # Every file the run staged, with its bytes.
  # sobelow_skip ["Traversal.FileModule"]
  defp staged(staging) do
    for path <- files(staging), into: %{}, do: {path, File.read!(Path.join(staging, path))}
  end

  defp push(_repo, %{remote_url: nil}), do: :ok
  defp push(_repo, nil), do: :ok

  # Her own remote (sima-qian#16): on Gitea, its push mirror, which Gitea
  # keeps in step on every commit (made or corrected here, idempotent); on
  # the disk, a push from the repository.
  defp push(repo, %{remote_url: url, remote_token: token}) do
    plain =
      case token && Vault.decrypt(token) do
        {:ok, p} when p != "" -> p
        _none -> nil
      end

    if Config.fetch!(:sima_qian, :repos_client) == Repos.Gitea do
      Repos.Gitea.mirror(repo, url, plain)
    else
      remote =
        case {plain, url} do
          {nil, _} -> url
          {p, "https://github.com/" <> _} -> Git.github_url(url, p)
          _ -> url
        end

      Git.push(Repos.Local.dir(repo), remote)
    end
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
