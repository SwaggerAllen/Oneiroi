defmodule Oneiroi.Seshat.Kinds do
  @moduledoc """
  The document kinds registry (spec §6.5, F27): path is kind, and the
  registry says what a kind may do. A document's kind comes from the
  first segment of its path and never from its content (conventions
  §11), so a file that calls itself writing in its frontmatter is still
  what its folder says it is.

  `cites` is which kinds mint citation edges: the resident-authored or
  commissioned ones (writing, design, research, journal). Mail, feeds,
  correspondence and the memory originals never do, whatever they contain, and the index
  deletes any edge it holds from them on every run. `access` is who
  writes the kind: `:resident` through a document write, `:core` by the
  platform (inbound for mail, feeds and correspondence; the journal for
  its narrative), `:imported` by nothing after the originals import
  copied it (memory, seshat#28), `:keepsake` once by either party and
  never again (seshat#29). The registry is platform-wide; adding a kind is a row
  here plus the brain's instruction for it (the tool description lists
  the writable kinds from this table).

  One kind has no folder: a keepsake is a text file at the repository's
  root, beside the soul file, under any name the root does not already
  give to something else (`reserved/0`). Its path is its name alone,
  so `kind_of/1` reads a one-segment text path as a keepsake and every
  other one-segment path as nothing.
  """

  alias Oneiroi.Seshat.Error

  @kinds [
    %{
      kind: "writing",
      folder: "writing",
      cites: true,
      has_status: true,
      layout: "writing/<slug>.md, frontmatter with status: draft | review | final | published",
      sidecar: nil,
      adoption: :file,
      access: :resident
    },
    # The oracle's answers (brain#49, seshat#34): an invocation of the
    # resident asked one question over her whole memory and the sources
    # named, its answer written here by the platform on her behalf and
    # attributed. Cites, so its sources are edges; out of the ranked
    # index's path, found deliberately (`oracles/2`).
    %{
      kind: "oracle",
      folder: "oracle",
      cites: true,
      has_status: false,
      layout:
        "oracle/<number>-<slug>.md: an oracle's answer, with its question, sources, confidence and dispatch",
      sidecar: nil,
      adoption: :none,
      access: :core
    },
    %{
      kind: "research",
      folder: "research",
      cites: true,
      has_status: false,
      layout: "research/<task>/<source>.md",
      sidecar: "task.md",
      adoption: :directory,
      access: :resident
    },
    %{
      kind: "design",
      folder: "design",
      cites: true,
      has_status: false,
      layout: "design/<name>.md",
      sidecar: nil,
      adoption: :file,
      access: :resident
    },
    %{
      kind: "journal",
      folder: "journal",
      cites: true,
      has_status: false,
      layout: "journal/<day>.md, rendered from the day's rows",
      sidecar: nil,
      adoption: :none,
      access: :core
    },
    # Decided, never swept (seshat#31): the wiki became the catch-all an
    # import landed everything homeless in, Pocket Andrew among it, so a
    # file enters it by a write or by its own adoption, never by an
    # import's whole-repository one.
    %{
      kind: "wiki",
      folder: "wiki",
      cites: false,
      has_status: false,
      layout: "wiki/<page>.md, plain and searchable (the memory-wiki plugin is cut)",
      sidecar: nil,
      adoption: :decided,
      access: :resident
    },
    # The resident's notes on how she runs (seshat#31): tool notes,
    # conventions, her own AGENTS.md beside the build's rendered one. Her
    # words about the machinery, apart from the soul file's voice, and
    # decided from the day it exists, so it cannot become the next
    # catch-all.
    %{
      kind: "system",
      folder: "system",
      cites: true,
      has_status: false,
      layout:
        "system/<name>.md: how the resident runs, in her words (tool notes, conventions, her AGENTS.md)",
      sidecar: nil,
      adoption: :decided,
      access: :resident
    },
    # Temporary documents (seshat#33): workshop state meant to go away
    # when its work is done, a scratch pad, a draft being argued over.
    # Removable, which no other kind is, and minting no citation edges,
    # since an edge to a page that will be removed dangles by design.
    %{
      kind: "scratch",
      folder: "scratch",
      cites: false,
      has_status: false,
      layout:
        "scratch/<name>.md: temporary workshop state (a scratch pad), removed when its work is done",
      sidecar: nil,
      adoption: :decided,
      access: :resident,
      removable: true
    },
    # The witness's own documents that belong nowhere else (seshat#33):
    # posts of theirs, notes, references they upload for the resident to
    # read. Written by the witness alone (`access: :witness`); the
    # resident reads and cites into them and never writes them, and the
    # witness's words mint no edges, as a sender's never do.
    %{
      kind: "human",
      folder: "human",
      cites: false,
      has_status: false,
      layout: "human/<name>.md: the witness's own documents that belong nowhere else",
      sidecar: nil,
      adoption: :decided,
      access: :witness,
      removable: true
    },
    %{
      kind: "posts",
      folder: "posts",
      cites: false,
      has_status: false,
      layout: "posts/<slug>.md, the published copies",
      sidecar: nil,
      adoption: :file,
      access: :resident
    },
    %{
      kind: "mail",
      folder: "mail",
      cites: false,
      has_status: false,
      layout: "mail/<thread>/<message>.md",
      sidecar: nil,
      adoption: :none,
      access: :core
    },
    %{
      kind: "feeds",
      folder: "feeds",
      cites: false,
      has_status: false,
      layout: "feeds/<feed>/<item>.md",
      sidecar: nil,
      adoption: :none,
      access: :core
    },
    %{
      kind: "correspondence",
      folder: "correspondence",
      cites: false,
      has_status: false,
      layout: "correspondence/<person>/<thread>.md",
      sidecar: nil,
      adoption: :none,
      access: :core
    },
    # The originals of the resident's daily memory from the platform it
    # was imported from (seshat#28): copied byte for byte from the
    # source at the commit the witness pins, with that provenance, and
    # never written after. `access: :imported` refuses every document
    # write, the platform's `core: true` included; `adoption: :originals`
    # keeps the ordinary adoption and import from registering one without
    # its provenance. No citation edges: the files were written against
    # the source platform's numbering, and an edge minted from one would
    # resolve against this platform's.
    %{
      kind: "memory",
      folder: "memory",
      cites: false,
      has_status: false,
      layout:
        "memory/<day>.md, memory/dreaming/**, and the source's root MEMORY.md and DREAMS.md under memory/, byte for byte at a pinned commit",
      sidecar: nil,
      adoption: :originals,
      access: :imported
    },
    # Her goals ledger (seshat#43, platform report #4): `<SLUG>-GOALS.md`
    # at the root, where brain#55 reads it each free-time turn, and hers
    # to edit at will. Before this it fell to the keepsake rule (any
    # other root text file is a keepsake, written once), so the ledger
    # froze after its first write and the reader and the writer
    # disagreed about what the file was for.
    %{
      kind: "goals",
      folder: nil,
      cites: false,
      has_status: false,
      layout:
        "<SLUG>-GOALS.md at the repository root (LILY-GOALS.md for Lily): the resident's own goals ledger, read in free time (brain#55), written at will",
      sidecar: nil,
      adoption: :decided,
      access: :resident
    },
    # The archive (seshat#45, platform report #5): where a document goes
    # when it is done with but must not be lost. Nothing is deleted: an
    # archived document keeps its words under `archive/<its old path>`,
    # with frontmatter saying who archived it, when and why; it leaves the
    # index (no search, no ranked recall) and is read at its path. Written
    # only by the archive act, never by a document write.
    %{
      kind: "archive",
      folder: "archive",
      cites: false,
      has_status: false,
      layout:
        "archive/<the old path>: an archived document, its words whole under frontmatter saying who, when and why; out of the index, read at its path",
      sidecar: nil,
      adoption: :decided,
      access: :core
    },
    # A root file (seshat#44, the witness's call 2026-11-07, platform
    # report #5): any text file at the root the reserved names and the
    # goals ledger do not claim, free to write. Placement alone no longer
    # makes a keepsake; a keepsake is a root file registered as one, a
    # deliberate act (`register_keepsake/4`), and the library's record of
    # each document's kind holds the list.
    %{
      kind: "root",
      folder: nil,
      cites: false,
      has_status: false,
      layout:
        "<name>.md at the repository root, beside the soul file; any name but the root's reserved ones; free to write until registered as a keepsake",
      sidecar: nil,
      adoption: :decided,
      access: :resident
    },
    # A keepsake (seshat#29): a gift-document kept at the root, beside
    # the soul file, where its placement is part of what it is. Pocket
    # Andrew was filed there on 2026-10-29 and moved under wiki/ by the
    # import of 2026-11-01 only because the library could not hold a
    # root file; the move kept the words and lost the place. Written
    # once by either party and never again (`access: :keepsake`), since
    # a gift edited is no longer the gift; a later version is a keepsake
    # of its own. `adoption: :decided`: an unregistered root file is
    # offered among the unadopted and adopted one by one, never by an
    # import's whole-repository adoption, so the root cannot become the
    # catch-all the wiki became. Cited, never citing: the words are
    # mostly the giver's.
    %{
      kind: "keepsake",
      folder: nil,
      cites: false,
      has_status: false,
      layout:
        "<name>.md at the repository root, beside the soul file; any name but the root's reserved ones",
      sidecar: nil,
      adoption: :decided,
      access: :keepsake
    }
  ]

  # The names the root already gives to something else: the identity
  # files (spec §6.2), the state store's STATE.md (agathos-daimon#32),
  # the build's rendered AGENTS.md, and the files
  # another platform's repository keeps there (David's README, MEMORY and
  # DREAMS, a coding agent's CLAUDE.md). None of them is a keepsake,
  # whatever it holds, and an import names each as it did before.
  @reserved ~w(SOUL.md IDENTITY.md USER.md GOALS.md LINKS.md STATE.md AGENTS.md README.md CLAUDE.md MEMORY.md DREAMS.md HEARTBEAT.md TOOLS.md)

  # A segment opens on a letter or digit, so `.`, `..` and a hidden file
  # fail here; a separate `..` clause was inert beside it and is gone.
  # Up to 255 characters, a filesystem's own bound on a name: the first
  # bound was 100, a guess, and it left behind a 104-character file of
  # Lily's wiki on the import's rehearsal. The whole path is bounded at
  # 255 too, the width of every `path` column the library writes
  # (`:string`, measured in the migration), which no check held before.
  @segment ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,254}\z/
  @path_max 255
  @text ~w(.md .markdown .txt)
  # A goals ledger's name (seshat#43): a slug in capitals, then -GOALS.md.
  @goals ~r/\A[A-Z0-9][A-Z0-9-]{0,200}-GOALS\.md\z/

  @doc "Every kind, in the registry's order."
  @spec all() :: [map()]
  def all, do: @kinds

  # The shelf (seshat#35): the order the kinds are shown in and what each
  # is called, one place on the server and never in a client. The gifts
  # first, the witness's own, the resident's work, the oracle's answers,
  # then what is meant to go and what arrives from outside. The
  # platform's default: when folders become each resident's to arrange,
  # this becomes theirs, and no client changes.
  @shelf [
    {"keepsake", "Keepsakes"},
    {"human", "Yours"},
    {"goals", "Goals"},
    {"root", "At the root"},
    {"archive", "Archive"},
    {"writing", "Writing"},
    {"design", "Design"},
    {"research", "Research"},
    {"oracle", "The oracle"},
    {"system", "System"},
    {"wiki", "Wiki"},
    {"posts", "Posts"},
    {"scratch", "Scratch"},
    {"journal", "Journal"},
    {"correspondence", "Correspondence"},
    {"mail", "Mail"},
    {"feeds", "Feeds"},
    {"memory", "Memory"}
  ]

  @doc "Every kind in the order it is shown, each with its `label` and `position` (seshat#35); a kind the shelf does not name comes last, under its own name."
  @spec shelf() :: [map()]
  def shelf do
    positions =
      @shelf |> Enum.with_index() |> Map.new(fn {{kind, label}, i} -> {kind, {i, label}} end)

    @kinds
    |> Enum.map(fn k ->
      {position, label} = Map.get(positions, k.kind, {length(@shelf), String.capitalize(k.kind)})
      Map.merge(k, %{label: label, position: position})
    end)
    |> Enum.sort_by(&{&1.position, &1.kind})
  end

  @doc "Whether a kind's documents may be removed (seshat#33): scratch and human, and nothing else."
  @spec removable?(map()) :: boolean()
  def removable?(kind), do: Map.get(kind, :removable, false)

  @doc "The kind a path belongs to, by its first segment, or nil; a path of one segment is a keepsake when it is a keepsake's name (`keepsake_name?/1`), and nothing otherwise."
  @spec kind_of(String.t()) :: map() | nil
  def kind_of(path) when is_binary(path) do
    case String.split(path, "/") do
      [name] ->
        cond do
          goals_name?(name) -> Enum.find(@kinds, &(&1.kind == "goals"))
          # A root file by its path; a keepsake only by registration (#44).
          keepsake_name?(name) -> Enum.find(@kinds, &(&1.kind == "root"))
          true -> nil
        end

      [folder | _rest] ->
        Enum.find(@kinds, &(&1.folder == folder and not is_nil(&1.folder)))
    end
  end

  @doc "The root names that are never keepsakes (seshat#29)."
  @spec reserved() :: [String.t()]
  def reserved, do: @reserved

  @doc """
  Whether a name at the repository root is a keepsake's: a text file
  (`text?/1`), a plain segment the registry accepts, and none of the
  root's reserved names. What the backup's keepsake class holds and what
  `unadopted/1` offers from the root.
  """
  @spec keepsake_name?(String.t()) :: boolean()
  def keepsake_name?(name) when is_binary(name) do
    Regex.match?(@segment, name) and text?(name) and name not in @reserved and
      not goals_name?(name)
  end

  def keepsake_name?(_other), do: false

  @doc """
  The kind an event recorded, as it reads now (seshat#44, the witness's
  call of 2026-11-07: nothing grandfathered): a document recorded as a
  keepsake by its place at the root, before registration existed, is a
  root file; only `KeepsakeRegistered` makes a keepsake. The events are
  unchanged.
  """
  @spec released(String.t()) :: String.t()
  def released("keepsake"), do: "root"
  def released(kind), do: kind

  @doc "Whether a root name is a resident's goals ledger, `<SLUG>-GOALS.md` (seshat#43)."
  @spec goals_name?(String.t()) :: boolean()
  def goals_name?(name) when is_binary(name), do: Regex.match?(@goals, name)
  def goals_name?(_other), do: false

  @doc "Whether a path is a keepsake's."
  @spec keepsake?(String.t()) :: boolean()
  def keepsake?(path) when is_binary(path), do: match?(%{kind: "keepsake"}, kind_of(path))

  @doc """
  Whether a path the library accepts belongs to a kind whose files are
  decided into it one by one (seshat#29, #31): the keepsakes, the wiki
  and the system shelf. An import leaves such a file where it is and the
  library offers it; nothing adopts it but its own adoption or a write.
  """
  @spec decided?(String.t()) :: boolean()
  def decided?(path) when is_binary(path),
    do: match?({:ok, _}, normalize(path)) and match?(%{adoption: :decided}, kind_of(path))

  def decided?(_other), do: false

  @doc "The kinds that mint citation edges."
  @spec minting() :: [String.t()]
  def minting, do: for(k <- @kinds, k.cites, do: k.kind)

  @doc "The kinds that never mint, whose edges the index deletes on every run."
  @spec non_minting() :: [String.t()]
  def non_minting, do: for(k <- @kinds, not k.cites, do: k.kind)

  @doc "The kinds a document write may land in (a keepsake once)."
  @spec writable() :: [String.t()]
  def writable, do: for(k <- @kinds, k.access in [:resident, :keepsake], do: k.kind)

  @doc """
  A path as the library accepts it: relative, plain segments (no `.`,
  `..` or empty), at most 255 characters each and 255 in all, under a
  registered folder or, alone, a keepsake's name at the root; nothing
  here reaches the filesystem unchecked.
  """
  @spec normalize(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def normalize(path) when is_binary(path) do
    segments = String.split(path, "/")

    cond do
      byte_size(path) > @path_max ->
        {:error, Error.new(:seshat_path_invalid, :seshat_kinds_path_too_long)}

      length(segments) < 2 and not (keepsake_name?(path) or goals_name?(path)) ->
        {:error, Error.new(:seshat_path_invalid, :seshat_kinds_path_no_folder, path: path)}

      not Enum.all?(segments, &Regex.match?(@segment, &1)) ->
        {:error, Error.new(:seshat_path_invalid, :seshat_kinds_path_segment_refused, path: path)}

      is_nil(kind_of(path)) ->
        {:error, Error.new(:seshat_path_invalid, :seshat_kinds_path_outside_folders, path: path)}

      true ->
        {:ok, path}
    end
  end

  def normalize(_other),
    do: {:error, Error.new(:seshat_path_invalid, :seshat_kinds_path_not_text)}

  @doc """
  Why the library cannot hold `path` from an import, in words a resident
  is told, or nil when it can: the reason an import gives for a file it
  leaves behind (sima-qian#22). A kind that takes only originals
  (memory) is held only through the originals import (seshat#28), so
  an import names each such file with that reason.
  """
  @spec refusal(String.t()) :: String.t() | nil
  def refusal(path) when is_binary(path) do
    if originals?(path),
      do:
        "the originals of memory come in through the originals import, at a commit the witness pins, never with the repository",
      else: path_refusal(path)
  end

  defp path_refusal(path) do
    segments = String.split(path, "/")

    cond do
      match?({:ok, _}, normalize(path)) ->
        nil

      path in @reserved ->
        "a file at the root that is not an identity file"

      is_nil(kind_of(path)) ->
        "outside the folders the library holds"

      Enum.any?(segments, &String.starts_with?(&1, ".")) ->
        "a hidden name, which the library does not hold"

      Enum.any?(segments, &(String.length(&1) > 255)) ->
        "a name longer than 255 characters"

      byte_size(path) > @path_max ->
        "a path longer than #{@path_max} characters"

      length(segments) < 2 ->
        "a folder's own name, not a file in it"

      true ->
        "a name with characters other than letters, digits, dot, dash and underscore"
    end
  end

  @doc "Whether a path's kind takes files only through the originals import, with their provenance (seshat#28)."
  @spec originals?(String.t()) :: boolean()
  def originals?(path) when is_binary(path), do: match?(%{adoption: :originals}, kind_of(path))

  @doc """
  Why the originals import cannot take `path` as a document, in words
  the witness is told, or nil when it can: the path refusals of
  `refusal/1` (a hidden name among them), a file the index cannot read
  as text, and a path outside the kinds that take originals.
  """
  @spec original_refusal(String.t()) :: String.t() | nil
  def original_refusal(path) when is_binary(path) do
    cond do
      reason = path_refusal(path) -> reason
      not originals?(path) -> "outside the folders that take originals"
      not text?(path) -> "not a text file (the library reads .md, .markdown and .txt)"
      true -> nil
    end
  end

  @doc "Whether the index reads a file as text to chunk and embed."
  @spec text?(String.t()) :: boolean()
  def text?(path), do: Path.extname(path) in @text
end
