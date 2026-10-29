defmodule Oneiroi.Seshat.Kinds do
  @moduledoc """
  The document kinds registry (spec §6.5, F27): path is kind, and the
  registry says what a kind may do. A document's kind comes from the
  first segment of its path and never from its content (conventions
  §11), so a file that calls itself writing in its frontmatter is still
  what its folder says it is.

  `cites` is which kinds mint citation edges: the resident-authored or
  commissioned ones (writing, design, research, journal). Mail, feeds
  and correspondence never do, whatever they contain, and the index
  deletes any edge it holds from them on every run. `access` is who
  writes the kind: `:resident` through a document write, `:core` by the
  platform (inbound for mail, feeds and correspondence; the journal for
  its narrative). The registry is platform-wide; adding a kind is a row
  here plus the brain's instruction for it (the tool description lists
  the writable kinds from this table).
  """

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
    %{
      kind: "wiki",
      folder: "wiki",
      cites: false,
      has_status: false,
      layout: "wiki/<page>.md, plain and searchable (the memory-wiki plugin is cut)",
      sidecar: nil,
      adoption: :file,
      access: :resident
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
    }
  ]

  # A segment opens on a letter or digit, so `.`, `..` and a hidden file
  # fail here; a separate `..` clause was inert beside it and is gone.
  @segment ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,99}\z/
  @text ~w(.md .markdown .txt)

  @doc "Every kind, in the registry's order."
  @spec all() :: [map()]
  def all, do: @kinds

  @doc "The kind a path belongs to, by its first segment, or nil."
  @spec kind_of(String.t()) :: map() | nil
  def kind_of(path) when is_binary(path) do
    folder = path |> String.split("/") |> hd()
    Enum.find(@kinds, &(&1.folder == folder))
  end

  @doc "The kinds that mint citation edges."
  @spec minting() :: [String.t()]
  def minting, do: for(k <- @kinds, k.cites, do: k.kind)

  @doc "The kinds that never mint, whose edges the index deletes on every run."
  @spec non_minting() :: [String.t()]
  def non_minting, do: for(k <- @kinds, not k.cites, do: k.kind)

  @doc "The kinds a document write may land in."
  @spec writable() :: [String.t()]
  def writable, do: for(k <- @kinds, k.access == :resident, do: k.kind)

  @doc """
  A path as the library accepts it: relative, plain segments (no `.`,
  `..` or empty), at most one hundred characters each, under a
  registered folder; nothing here reaches the filesystem unchecked.
  """
  @spec normalize(term()) :: {:ok, String.t()} | {:error, :path_invalid}
  def normalize(path) when is_binary(path) do
    segments = String.split(path, "/")

    cond do
      length(segments) < 2 -> {:error, :path_invalid}
      not Enum.all?(segments, &Regex.match?(@segment, &1)) -> {:error, :path_invalid}
      is_nil(kind_of(path)) -> {:error, :path_invalid}
      true -> {:ok, path}
    end
  end

  def normalize(_other), do: {:error, :path_invalid}

  @doc "Whether the index reads a file as text to chunk and embed."
  @spec text?(String.t()) :: boolean()
  def text?(path), do: Path.extname(path) in @text
end
