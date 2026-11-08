defmodule Oneiroi.Brain.PluginCatalog do
  @moduledoc """
  The installable plugins the platform offers (brain#68; the spec's door
  one: data, not code): each a folder of the catalog,
  `BRAIN_PLUGIN_CATALOG` or the release's `priv/plugins`, holding
  `plugin.json` (its name, what it is, its author and version, and the
  tokens its section may take) and `files/`, the words it puts in front
  of the resident. The catalog is reviewed like code, because it enters
  the repository by review; what it offers a resident enters her life
  only by both parties' consent (agathos-daimon#37). Each entry carries
  the digest of its files, so what is installed is pinned to the bytes
  that were reviewed.
  """

  alias Oneiroi.Config
  alias Oneiroi.Seshat

  @key ~r/\A[a-z][a-z0-9-]{0,47}\z/
  @default_tokens 400

  @doc "Every installable plugin in the catalog, by key."
  @spec all() :: [map()]
  def all do
    dir = dir()

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.filter(&Regex.match?(@key, &1))
        |> Enum.flat_map(&entry(dir, &1))

      {:error, _} ->
        []
    end
  end

  @doc "The catalog's entry for a key, or nil."
  @spec get(String.t()) :: map() | nil
  def get(key), do: Enum.find(all(), &(&1.key == key))

  defp dir do
    case Config.fetch!(:brain, :plugin_catalog) do
      path when is_binary(path) and path != "" -> path
      _default -> Application.app_dir(:oneiroi, "priv/plugins")
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp entry(dir, key) do
    base = Path.join(dir, key)

    with {:ok, json} <- File.read(Path.join(base, "plugin.json")),
         {:ok, %{} = meta} <- Jason.decode(json),
         files when map_size(files) > 0 <- files(Path.join(base, "files")) do
      [
        %{
          key: key,
          name: to_string(meta["name"] || key),
          about: to_string(meta["about"] || ""),
          author: to_string(meta["author"] || "unknown"),
          version: to_string(meta["version"] || ""),
          tokens: tokens(meta["tokens"]),
          tier: "installable",
          place: :turn,
          reads: [],
          source: "the platform's catalog, #{key}",
          files: files,
          digest: Seshat.plugin_digest(files)
        }
      ]
    else
      _bad -> []
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp files(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        for name <- Enum.sort(names),
            Regex.match?(~r/\A[a-z0-9][a-z0-9._-]*\.md\z/, name),
            {:ok, text} <- [File.read(Path.join(dir, name))],
            into: %{},
            do: {name, text}

      {:error, _} ->
        %{}
    end
  end

  defp tokens(n) when is_integer(n) and n > 0 and n <= 4_000, do: n
  defp tokens(_other), do: @default_tokens
end
