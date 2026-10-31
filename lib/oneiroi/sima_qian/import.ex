defmodule Oneiroi.SimaQian.Import do
  @moduledoc """
  The intake from a repository (spec §6.2's fourth path, §9): what the
  rebuild does and then the rest of the repository. A repository with
  `records/events/` replays as the rebuild does; one without is a
  resident created here under the name and slug the witness gives.
  Either way the clone becomes the resident's working repository, so
  its history carries on; the identity files at its root are seeded
  (`uploaded`), or proposed where the records say first contact has
  passed and the file differs; every file under a kind's folder is
  adopted through the library port and indexed once; and what at the
  root is none of those is listed by name as not transferred. The
  import's second half is `ImportCompleted` on the resident's stream,
  and the brain tells the resident where it woke on its first turn
  (brain #26).

  Two things a request value never does here: name a path (the URL
  must carry one of the configured schemes, so a witness cannot clone
  a directory on this host, another resident's working repository
  among them), or enter the log (the source is recorded with its
  userinfo stripped, because a GitHub URL carries the token there and
  the `Imported` event is exported).
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.David
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Rebuild

  # Covered without being named: Oneiroi's own records and the Honcho
  # files the export rewrites, but only when the source is an Oneiroi
  # export (it has `records/events/`). A repository from elsewhere keeps
  # its own `records/` and `honcho/`, so they are named like any other
  # root entry: Lily's held David's bookmarks, positions and transcripts
  # under `records/`, and the first reading of this rule left them out
  # of the list without a word. David's are now translated (sima-qian
  # #19), and `records/` is covered when they were.
  @oneiroi_files ["records", "honcho"]

  @doc "Imports the repository at `url` as a new resident under `witness_account_id`."
  # The clone is this function's own under the temp dir; the working
  # directory it becomes is the records root under an id minted here.
  # sobelow_skip ["Traversal.FileModule"]
  def run(url, attrs, witness_account_id, %Actor{} = actor)
      when is_binary(url) and is_map(attrs) do
    clone = Path.join(System.tmp_dir!(), "oneiroi-import-#{System.unique_integer([:positive])}")
    source = record_url(url)

    try do
      with :ok <- scheme_ok(url),
           :ok <- Git.clone(url, clone),
           {attestation, root, sequence} <- Rebuild.attestation(clone),
           :ok <- Rebuild.refuse_if_imported(source, root),
           {:ok, lines} <- Rebuild.read_lines(clone),
           {:ok, id, how} <- resident(lines, attrs, witness_account_id, actor),
           {:ok, _} <- Rebuild.import_event(id, source, attestation, root, sequence, actor),
           :ok <- custody(how, id, witness_account_id, actor),
           :ok <- place(clone, id),
           {:ok, seeds} <- seeds(id, clone, actor),
           {:ok, translated} <- translate(how, id, witness_account_id, actor),
           {:ok, adopted} <- library().adopt_all(id, actor),
           not_transferred =
             not_transferred(clone, translated, seeds.kept ++ adopted.skipped),
           :ok <-
             AgathosDaimon.complete_import(
               id,
               seeds.seeded,
               length(adopted.adopted),
               not_transferred,
               translated && Map.take(translated, [:source, :counts]),
               actor
             ) do
        :telemetry.execute(
          [:oneiroi, :sima_qian, :import],
          %{events: length(lines), adopted: length(adopted.adopted)},
          %{resident_id: id}
        )

        {:ok,
         %{
           id: id,
           attestation: attestation,
           root: root,
           events: length(lines),
           seeded: seeds.seeded,
           proposed: seeds.proposed,
           adopted: length(adopted.adopted),
           indexed: adopted.indexed,
           translated: translated && Map.take(translated, [:source, :counts]),
           not_transferred: not_transferred
         }}
      end
    after
      File.rm_rf(clone)
    end
  end

  @doc "The URL as the log records it: userinfo stripped, because a GitHub URL carries the token there."
  @spec record_url(String.t()) :: String.t()
  def record_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} = uri when is_binary(scheme) -> URI.to_string(%{uri | userinfo: nil})
      _bare -> url
    end
  end

  defp scheme_ok(url) do
    schemes = Config.fetch!(:sima_qian, :import_schemes)

    case URI.parse(url) do
      %URI{scheme: scheme} when is_binary(scheme) ->
        if scheme in schemes,
          do: :ok,
          else: {:error, Error.new(:sima_qian_scheme_refused, scheme: scheme, schemes: schemes)}

      _bare ->
        {:error, Error.new(:sima_qian_scheme_refused, scheme: nil, schemes: schemes)}
    end
  end

  # A repository with records replays them under a new id, and its name
  # and slug are the records'; one without is created here and needs
  # both from the witness.
  defp resident([], attrs, witness_account_id, actor) do
    name = Map.get(attrs, :name) || Map.get(attrs, "name")
    slug = Map.get(attrs, :slug) || Map.get(attrs, "slug")

    if is_binary(name) and is_binary(slug) do
      with {:ok, id} <- AgathosDaimon.create(name, slug, witness_account_id, actor),
           do: {:ok, id, :created}
    else
      {:error, Error.new(:sima_qian_name_required)}
    end
  end

  defp resident(lines, _attrs, _witness_account_id, _actor) do
    id = Ecto.UUID.generate()
    with :ok <- Rebuild.append(id, lines), do: {:ok, id, :replayed}
  end

  # A resident created here is the witness's already; a replayed one is
  # placed with the importing witness as the rebuild places it.
  defp custody(:created, _id, _witness_account_id, _actor), do: :ok

  defp custody(:replayed, id, witness_account_id, actor),
    do: with({:ok, _} <- Rebuild.custody(id, witness_account_id, actor), do: :ok)

  # The clone becomes the working repository, history and all, so the
  # next backup commits on top of the source's commits. The origin
  # remote goes with the clone's config, where the clone URL (and any
  # token in it) would otherwise sit on disk until the witness sets a
  # remote of their own.
  # sobelow_skip ["Traversal.FileModule"]
  defp place(clone, id) do
    dest = Backup.dir(id)
    File.mkdir_p!(Path.dirname(dest))

    case File.cp_r(clone, dest) do
      {:ok, _copied} -> Git.forget_remote(dest)
      {:error, reason, path} -> {:error, {:copy, reason, path}}
    end
  end

  # The identity files at the root, seeded as uploaded; where the
  # records say first contact has passed and the file differs from
  # them, a witness's write is a proposal (spec §6.2), and the import
  # files one rather than overwriting or dropping it. A file the
  # aggregate refuses for its content is kept, by name, for the
  # not-transferred list.
  # sobelow_skip ["Traversal.FileModule"]
  defp seeds(id, clone, actor) do
    AgathosDaimon.identity_files()
    |> Enum.filter(&File.regular?(Path.join(clone, &1)))
    |> Enum.reduce_while({:ok, %{seeded: [], proposed: [], kept: []}}, fn name, {:ok, acc} ->
      case seed(id, name, File.read!(Path.join(clone, name)), actor) do
        {:ok, key} -> {:cont, {:ok, Map.update!(acc, key, &(&1 ++ [name]))}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp seed(id, name, content, actor) do
    case AgathosDaimon.write_file(id, name, content, %{origin: "uploaded"}, actor) do
      :ok ->
        {:ok, :seeded}

      {:error, %{kind: :agathos_daimon_propose_instead}} ->
        note = "found at the repository's root on import, differing from the records"

        with {:ok, _ref} <- AgathosDaimon.propose_edit(id, name, content, note, actor),
             do: {:ok, :proposed}

      {:error, %{kind: :agathos_daimon_content_invalid}} ->
        {:ok, :kept}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Another platform's records, made into this one's (sima-qian #19):
  # David's, the one platform whose export this reads, in a repository
  # created here rather than replayed. Read from the working repository
  # the clone became, before the library adopts, so the journal days the
  # notes become are written before the adoption looks for files.
  defp translate(:created, id, witness_account_id, actor) do
    dir = Backup.dir(id)

    if David.present?(dir),
      do: David.translate(id, dir, witness_account_id, actor),
      else: {:ok, nil}
  end

  defp translate(:replayed, _id, _witness_account_id, _actor), do: {:ok, nil}

  # Everything at the root that is not an identity file, a kind's
  # folder or (in an Oneiroi export) the records and the Honcho files,
  # plus what was kept or skipped on the way: named, sorted, and told.
  # When another platform's records were translated, `records/` is
  # covered and what in it nothing read is named file by file instead.
  # sobelow_skip ["Traversal.FileModule"]
  defp not_transferred(clone, translated, extra) do
    ours =
      cond do
        File.dir?(Path.join([clone, "records", "events"])) -> @oneiroi_files
        translated -> ["records"]
        true -> []
      end

    extra = if translated, do: translated.unread ++ extra, else: extra
    covered = [".git" | ours] ++ AgathosDaimon.identity_files() ++ library().folders()

    clone
    |> File.ls!()
    |> Enum.reject(&(&1 in covered))
    |> Kernel.++(extra)
    |> Enum.sort()
  end

  defp library, do: Config.fetch!(:sima_qian, :library)
end
