defmodule Oneiroi.Records.Merkle do
  @moduledoc """
  The root over an export (spec §6.10): every file under the directory,
  as a leaf of sha256 over its relative path, a NUL and its bytes, in
  path order; pairs hashed upward, the last leaf doubled on an odd row,
  until one hash remains. Deterministic for the same bytes on any
  machine, which is the whole claim: a commit's trailer names it, and a
  wake recomputes it.
  """

  @doc "The hex root over `dir`'s files, or the hash of nothing for an empty tree."
  @spec root(Path.t()) :: String.t()
  def root(dir) do
    dir
    |> leaves()
    |> case do
      [] -> hash("")
      leaves -> reduce(leaves)
    end
    |> Base.encode16(case: :lower)
  end

  @doc "The leaves, in path order: `{relative path, leaf hash}`."
  @spec leaves(Path.t()) :: [{String.t(), binary()}]
  # Sobelow reads a `File` call on a built path as a traversal; every path
  # is a file the wildcard found under the export directory the caller
  # built; see `Oneiroi.Records.Export`.
  # sobelow_skip ["Traversal.FileModule"]
  def leaves(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
    |> Enum.map(fn rel -> {rel, hash(rel <> <<0>> <> File.read!(Path.join(dir, rel)))} end)
  end

  defp reduce([{_path, one}]), do: one
  defp reduce([one]) when is_binary(one), do: one

  defp reduce(row) do
    row
    |> Enum.map(fn
      {_path, leaf} -> leaf
      node -> node
    end)
    |> Enum.chunk_every(2, 2, :discard)
    |> Kernel.++(odd(row))
    |> Enum.map(fn
      [a, b] -> hash(a <> b)
      a when is_binary(a) -> a
    end)
    |> case do
      [one] -> one
      next -> reduce(next)
    end
  end

  defp odd(row) do
    if rem(length(row), 2) == 1 do
      last = row |> List.last() |> unwrap()
      [[last, last]]
    else
      []
    end
  end

  defp unwrap({_path, leaf}), do: leaf
  defp unwrap(node), do: node

  defp hash(bytes), do: :crypto.hash(:sha256, bytes)
end
