defmodule Oneiroi.Seshat.PluginFiles do
  @moduledoc """
  An installable plugin's files in the resident's library (seshat#47,
  brain#68): written under `plugins/<key>/` when both parties install
  it, with `PLUGIN.md`, its lockfile (the source, the version, the
  digest of what was installed and when), and removed when both agree.
  The lockfile is the record in her repository of what she consented
  to, byte for byte: a copy whose words no longer match it is said, not
  trusted (verify by content, not by name).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Store

  @doc "The digest of a set of files: SHA-256 over each path and its words, in path order."
  @spec digest(%{String.t() => String.t()}) :: String.t()
  def digest(files) do
    files
    |> Enum.sort()
    |> Enum.map_join(<<0>>, fn {path, text} -> path <> <<0>> <> text end)
    |> then(&("sha256:" <> Base.encode16(:crypto.hash(:sha256, &1), case: :lower)))
  end

  @doc """
  Writes a plugin's files and its lockfile under `plugins/<key>/`;
  `meta` is the catalog entry's name, author, version and source. The
  digest written.
  """
  def install(resident_id, key, %{} = files, %{} = meta, %Actor{} = actor) do
    digest = digest(files)

    with :ok <- write_all(resident_id, key, files, actor),
         {:ok, _} <-
           Documents.write(
             resident_id,
             "plugins/#{key}/PLUGIN.md",
             lockfile(key, files, meta, digest),
             actor,
             core: true
           ) do
      {:ok, digest}
    end
  end

  @doc "Removes every file under `plugins/<key>/`, the lockfile last."
  def remove(resident_id, key, %Actor{} = actor) do
    resident_id
    |> paths(key)
    |> Enum.sort_by(&String.ends_with?(&1, "/PLUGIN.md"))
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case Documents.remove(resident_id, path, actor) do
        :ok -> {:cont, :ok}
        {:error, _} = failed -> {:halt, failed}
      end
    end)
  end

  @doc """
  The plugin's files as they stand in her library, beside the lockfile's
  digest: `%{files: %{path => words}, pinned: digest | nil, found: digest}`.
  """
  def read(resident_id, key) do
    texts =
      for path <- paths(resident_id, key),
          not String.ends_with?(path, "/PLUGIN.md"),
          {:ok, %{content: words}} <- [Documents.fetch(resident_id, path)],
          into: %{},
          do: {String.replace_prefix(path, "plugins/#{key}/", ""), words}

    pinned =
      case Documents.fetch(resident_id, "plugins/#{key}/PLUGIN.md") do
        {:ok, %{content: lock}} ->
          case Regex.run(~r/^digest: (sha256:[0-9a-f]{64})$/m, lock) do
            [_, d] -> d
            nil -> nil
          end

        _absent ->
          nil
      end

    %{files: texts, pinned: pinned, found: digest(texts)}
  end

  defp paths(resident_id, key) do
    prefix = "plugins/#{key}/"

    resident_id
    |> then(&Scope.resident(&1, fn -> Store.documents() end))
    |> Enum.map(& &1.path)
    |> Enum.filter(&String.starts_with?(&1, prefix))
  end

  defp write_all(resident_id, key, files, actor) do
    Enum.reduce_while(Enum.sort(files), :ok, fn {path, words}, :ok ->
      case Documents.write(resident_id, "plugins/#{key}/#{path}", words, actor, core: true) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = failed -> {:halt, failed}
      end
    end)
  end

  defp lockfile(key, files, meta, digest) do
    listed = files |> Map.keys() |> Enum.sort() |> Enum.map_join("\n", &"  - #{&1}")

    """
    ---
    plugin: #{key}
    name: #{inspect(meta[:name] || key)}
    author: #{inspect(meta[:author] || "unknown")}
    version: #{inspect(meta[:version] || "")}
    source: #{inspect(meta[:source] || "the platform's catalog")}
    digest: #{digest}
    installed_at: #{DateTime.to_iso8601(Clock.now())}
    files:
    #{listed}
    ---

    # #{meta[:name] || key}

    Installed by both of you. These files are the plugin's words, not
    yours; what you keep of them is yours to bookmark. The digest above is
    what was installed: a copy that no longer matches it is said so.
    """
  end
end
