defmodule Oneiroi.SimaQian.Originals do
  @moduledoc """
  The originals import (sima-qian #40): the files of the resident's
  daily memory taken from its import source byte for byte, at the commit
  the witness pins, into the working repository's `memory/` folder, and
  registered through the library port with where each came from.

  The import of a repository took every folder the library holds and
  left the rest behind by name; the source's `memory/` was not one of
  them, so its day files and their projections reached the library only
  through copies another platform had made of them, some cut short and
  some never made. This reads the originals instead, and only at a
  commit: the source keeps changing after the fork, and what is asked
  for is identity with the source up to the fork, not with its head.

  Every step is a check before the next. The commit is fetched by its
  full name, one commit deep, never a branch. A path is taken when one
  of the patterns matches it, and lands under `memory/` keeping its name
  (`memory/...` as it is, any other path under `memory/`: the source's
  root `MEMORY.md` is `memory/MEMORY.md`). A file already in the
  repository with the same bytes is left as it is; one with other bytes
  is refused and never overwritten. Each file this run wrote is hashed
  as git hashes a blob and compared with the source tree's blob; one
  mismatch removes what this run wrote and adopts nothing. Then the
  library registers each with its provenance and indexes once.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Import

  @default_paths ["memory/*.md", "memory/dreaming/**", "MEMORY.md", "DREAMS.md"]
  @folder "memory/"
  @sha ~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/

  @doc "The patterns taken when a request names none: the day files, the dreaming folder, and the two root files."
  @spec default_paths() :: [String.t()]
  def default_paths, do: @default_paths

  @doc """
  Imports the originals at `commit` of `source` for `resident_id`.
  `token` is a `Secret` or nil; it reaches git only through its
  credential file (`Git.credentialed/2`) and is never recorded: the
  provenance names the source without userinfo. `write` is the copy,
  `File.write/2` but for the suite, which hands it a copy that tampers.
  """
  # Sobelow reads a `File` call on a built path as a traversal; every
  # path here is the records root under a resident id the platform
  # minted, joined with a path the library port accepted, or this run's
  # own directory under the temp dir.
  # sobelow_skip ["Traversal.FileModule"]
  def run(resident_id, request, actor, write \\ &File.write/2)

  # sobelow_skip ["Traversal.FileModule"]
  def run(resident_id, request, %Actor{kind: :witness} = actor, write) do
    tmp = Path.join(System.tmp_dir!(), "oneiroi-originals-#{System.unique_integer([:positive])}")

    try do
      with {:ok, source, commit, patterns} <- request(request),
           :ok <- Import.scheme_ok(source),
           :ok <- Git.fetch_commit(remote(source, request[:token]), commit, tmp),
           {:ok, tree} <- Git.tree(tmp, commit),
           {:ok, dir} <- Backup.repository_dir(resident_id) do
        {chosen, skipped} = choose(tree, patterns)
        {placed, refused} = place(tmp, dir, chosen, write)

        with :ok <- verify(tmp, dir, placed),
             provenance = provenance(Git.public_url(source), commit),
             files = Enum.map(placed, &%{path: &1.dest, provenance: provenance.(&1)}),
             {:ok, adopted} <- library().adopt_originals(resident_id, files, actor) do
          {:ok,
           %{
             source: Git.public_url(source),
             commit: commit,
             written: for(p <- placed, p.written, do: p.dest),
             unchanged: for(p <- placed, not p.written, do: p.dest),
             adopted: adopted.adopted,
             indexed: adopted.indexed,
             mapped: Map.new(chosen, &{&1.path, &1.dest}),
             refused: Map.new(refused),
             skipped: Map.new(skipped)
           }}
        end
      end
    after
      File.rm_rf(tmp)
    end
  end

  def run(_resident_id, _request, %Actor{}, _write),
    do: {:error, Error.new(:sima_qian_not_the_witness, :sima_qian_originals_witness_only)}

  defp request(request) do
    source = request[:source]
    commit = request[:commit]
    patterns = request[:paths] || @default_paths

    cond do
      not is_binary(source) ->
        {:error, Error.new(:sima_qian_scheme_refused, :sima_qian_originals_no_source)}

      not (is_binary(commit) and Regex.match?(@sha, commit)) ->
        {:error, Error.new(:sima_qian_commit_invalid, :sima_qian_originals_commit_invalid)}

      not (is_list(patterns) and patterns != [] and Enum.all?(patterns, &pattern?/1)) ->
        {:error, Error.new(:sima_qian_paths_invalid, :sima_qian_originals_paths_invalid)}

      true ->
        {:ok, source, commit, patterns}
    end
  end

  # A pattern names paths inside the source tree: relative, no `..`.
  defp pattern?(p) when is_binary(p) and p != "" do
    not String.starts_with?(p, "/") and ".." not in String.split(p, "/")
  end

  defp pattern?(_other), do: false

  defp remote(source, nil), do: source
  defp remote(source, %Secret{} = token), do: Git.github_url(source, Secret.reveal(token))

  # Which entries of the tree are taken, and why each one under
  # `memory/` or matched by a pattern is not: outside the set, a link or
  # a submodule rather than a file, a name the library refuses (hidden,
  # not text), or a second source for one destination.
  defp choose(tree, patterns) do
    regexes = Enum.map(patterns, &glob/1)

    {chosen, skipped, _dests} =
      Enum.reduce(tree, {[], [], MapSet.new()}, fn entry, {chosen, skipped, dests} ->
        matched? = Enum.any?(regexes, &Regex.match?(&1, entry.path))
        dest = destination(entry.path)

        case reason(entry, dest, matched?, dests) do
          nil ->
            {[Map.put(entry, :dest, dest) | chosen], skipped, MapSet.put(dests, dest)}

          :ignored ->
            {chosen, skipped, dests}

          why ->
            {chosen, [{entry.path, why} | skipped], dests}
        end
      end)

    {Enum.reverse(chosen), Enum.reverse(skipped)}
  end

  defp reason(entry, dest, matched?, dests) do
    cond do
      not matched? and String.starts_with?(entry.path, @folder) -> "outside the set asked for"
      not matched? -> :ignored
      entry.type != "blob" -> "a submodule, not a file"
      entry.mode == "120000" -> "a symbolic link, not a file"
      why = library().original_refusal(dest) -> why
      MapSet.member?(dests, dest) -> "another source path lands on #{dest}"
      true -> nil
    end
  end

  @doc "Where a source path lands: a path under `memory/` as it is, any other path under `memory/` keeping its name."
  @spec destination(String.t()) :: String.t()
  def destination(path),
    do: if(String.starts_with?(path, @folder), do: path, else: @folder <> path)

  # `**` is any run of characters, slashes included; `*` stays within a
  # segment; everything else is literal.
  defp glob(pattern) do
    body =
      pattern
      |> String.split("**")
      |> Enum.map_join(".*", fn part ->
        part |> String.split("*") |> Enum.map_join("[^/]*", &Regex.escape/1)
      end)

    Regex.compile!("\\A" <> body <> "\\z")
  end

  # Each chosen file copied unless the repository has it already: the
  # same bytes stand (a re-run changes nothing), other bytes are refused
  # and never overwritten.
  # sobelow_skip ["Traversal.FileModule"]
  defp place(tmp, dir, chosen, write) do
    Enum.reduce(chosen, {[], []}, fn entry, {placed, refused} ->
      full = Path.join(dir, entry.dest)

      cond do
        File.exists?(full) and Git.blob_sha(tmp, full) == {:ok, entry.blob} ->
          {placed ++ [Map.put(entry, :written, false)], refused}

        File.exists?(full) ->
          {placed,
           refused ++
             [{entry.dest, "in the repository already with other bytes; not overwritten"}]}

        true ->
          {:ok, bytes} = Git.blob(tmp, entry.blob)
          File.mkdir_p!(Path.dirname(full))
          :ok = write.(full, bytes)
          {placed ++ [Map.put(entry, :written, true)], refused}
      end
    end)
  end

  # Every placed file hashed as git hashes a blob and held to the source
  # tree's blob; any mismatch removes what this run wrote, so nothing is
  # adopted and nothing of the run is left on disk.
  # sobelow_skip ["Traversal.FileModule"]
  defp verify(tmp, dir, placed) do
    mismatched =
      for p <- placed, Git.blob_sha(tmp, Path.join(dir, p.dest)) != {:ok, p.blob}, do: p.dest

    if mismatched == [] do
      :ok
    else
      for p <- placed, p.written, do: File.rm(Path.join(dir, p.dest))

      {:error,
       Error.new(:sima_qian_original_mismatch, :sima_qian_originals_blob_mismatch,
         paths: mismatched
       )}
    end
  end

  defp provenance(source, commit),
    do: fn entry -> %{source: source, commit: commit, path: entry.path, blob: entry.blob} end

  defp library, do: Config.fetch!(:sima_qian, :library)
end
