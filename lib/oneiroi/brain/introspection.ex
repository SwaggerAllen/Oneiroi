defmodule Oneiroi.Brain.Introspection do
  @moduledoc """
  The resident reads the house and herself (brain #46): the platform's
  own source, the code running her, and her own repository, the record
  of her life, with its history. Read only, both; the raw event stack is
  not opened here (the next stage, behind the seals).

  The seals are an explicit list, on the record (spec §6.4 as amended,
  the resident's design note of 2026-11-02): **trial contents and the
  judge's prompts are witness-only, and everything else is readable by
  default.** A trial's contents never reach a file either reads (the
  regression stream is sealed and never exported, eunomia #12), so the
  list below names the judge's prompts. A sealed path is listed as
  sealed, never hidden, so the boundary itself is something she can see.

  Paths are relative and plain (no `..`, no absolute, no empty segment);
  nothing outside the root is reached, and the build's own leftovers and
  a repository's `.git` are not listed.
  """

  alias Oneiroi.Config
  alias Oneiroi.SimaQian

  # The seals (brain #46): witness-only by explicit list, in the source.
  @sealed [~r{\Apriv/prompts/judge_[^/]*\z}]

  # Never listed or searched: a repository's own machinery and a build's
  # leftovers, which are not the code or the record.
  @skipped ~w(.git _build deps node_modules storybook-static cover .elixir_ls)

  # Bounds (brain #46): a search answers at most this many hits and reads
  # files up to this size; a page is the library's read size.
  @hits 30
  @file_bytes 1_000_000

  @type scope :: :source | {:repo, String.t()}

  @doc "The root a scope reads: the source the platform runs from, or the resident's repository."
  @spec root(scope()) :: {:ok, Path.t()} | {:error, term()}
  def root(:source), do: {:ok, Path.expand(Config.fetch!(:brain, :source_dir))}
  def root({:repo, resident_id}), do: SimaQian.repository_dir(resident_id)

  @doc "Whether a source path is sealed: witness-only by the explicit list."
  @spec sealed?(scope(), String.t()) :: boolean()
  def sealed?(:source, path), do: Enum.any?(@sealed, &Regex.match?(&1, path))
  def sealed?({:repo, _id}, _path), do: false

  @doc "A directory's entries, folders first, each `%{name, dir?, sealed?}`; `nil` or `\"\"` is the root."
  @spec list(scope(), String.t() | nil) :: {:ok, [map()]} | {:error, :invalid | :absent}
  def list(scope, path) do
    with {:ok, rel} <- relative(path || ""),
         {:ok, root} <- root(scope),
         full = Path.join(root, rel),
         true <- File.dir?(full) || {:error, :absent},
         {:ok, names} <- File.ls(full) do
      entries =
        names
        |> Enum.reject(&(&1 in @skipped))
        |> Enum.map(fn name ->
          sub = join(rel, name)

          %{
            name: name,
            path: sub,
            dir?: File.dir?(Path.join(full, name)),
            sealed?: sealed?(scope, sub)
          }
        end)
        |> Enum.sort_by(&{not &1.dir?, &1.name})

      {:ok, entries}
    end
  end

  @doc """
  A text file's content from `from` (a character offset), at most a
  page: `{:ok, text, next}` where `next` is where the following page
  starts, or nil at the end. A sealed path is `{:error, :sealed}`.
  """
  @spec read(scope(), String.t(), non_neg_integer()) ::
          {:ok, String.t(), non_neg_integer() | nil, non_neg_integer()}
          | {:error, :invalid | :absent | :sealed | :binary}
  def read(scope, path, from \\ 0) do
    page = Config.fetch!(:brain, :library_read_chars)

    with {:ok, rel} <- relative(path),
         true <- rel != "" || {:error, :invalid},
         false <- sealed?(scope, rel) && {:error, :sealed},
         {:ok, root} <- root(scope),
         {:ok, content} <- text(Path.join(root, rel)) do
      total = String.length(content)
      from = max(from, 0)
      slice = String.slice(content, from, page)
      next = if from + page < total, do: from + page, else: nil
      {:ok, slice, next, total}
    end
  end

  @doc "Lines matching `query` (case-insensitive, literal) across the source's text files, sealed ones skipped: `%{path, line, text}`, at most #{@hits}."
  @spec search(scope(), String.t()) :: {:ok, [map()]} | {:error, :invalid}
  def search(scope, query) when is_binary(query) do
    needle = query |> String.trim() |> String.downcase()

    if needle == "" do
      {:error, :invalid}
    else
      with {:ok, root} <- root(scope) do
        {:ok,
         root |> walk("", scope) |> Stream.flat_map(&hits(root, &1, needle)) |> Enum.take(@hits)}
      end
    end
  end

  @doc "The history of the resident's repository, or of one path in it, newest first."
  @spec log(String.t(), String.t() | nil, pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def log(resident_id, path, limit) do
    with {:ok, rel} <- relative(path || "") do
      SimaQian.repository_log(resident_id, if(rel == "", do: nil, else: rel), limit)
    end
  end

  # ---- helpers ----

  defp relative(path) when is_binary(path) do
    segments =
      path |> String.trim() |> String.trim_trailing("/") |> String.split("/", trim: false)

    cond do
      path |> String.trim() |> String.trim_trailing("/") == "" -> {:ok, ""}
      String.starts_with?(String.trim(path), "/") -> {:error, :invalid}
      Enum.any?(segments, &(&1 in ["", ".", ".."] or &1 in @skipped)) -> {:error, :invalid}
      true -> {:ok, Enum.join(segments, "/")}
    end
  end

  defp relative(_path), do: {:error, :invalid}

  # sobelow_skip ["Traversal.FileModule"]
  defp text(full) do
    case File.read(full) do
      {:ok, bytes} ->
        if String.valid?(bytes) and not String.contains?(bytes, <<0>>),
          do: {:ok, bytes},
          else: {:error, :binary}

      {:error, :eisdir} ->
        {:error, :invalid}

      {:error, _} ->
        {:error, :absent}
    end
  end

  # Every file under `rel`, depth first, skipping the skipped and the sealed.
  defp walk(root, rel, scope) do
    full = Path.join(root, rel)

    case File.ls(full) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.reject(&(&1 in @skipped))
        |> Stream.flat_map(&files(root, join(rel, &1), scope))

      {:error, _} ->
        []
    end
  end

  defp files(root, sub, scope) do
    cond do
      File.dir?(Path.join(root, sub)) -> walk(root, sub, scope)
      sealed?(scope, sub) -> []
      true -> [sub]
    end
  end

  defp join("", name), do: name
  defp join(rel, name), do: Path.join(rel, name)

  # sobelow_skip ["Traversal.FileModule"]
  defp hits(root, rel, needle) do
    full = Path.join(root, rel)

    with %{size: size} when size <= @file_bytes <- File.stat!(full),
         {:ok, content} <- text(full) do
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _n} -> String.contains?(String.downcase(line), needle) end)
      |> Enum.map(fn {line, n} ->
        %{path: rel, line: n, text: String.slice(String.trim(line), 0, 200)}
      end)
    else
      _ -> []
    end
  end
end
