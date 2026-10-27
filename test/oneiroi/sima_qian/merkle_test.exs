defmodule Oneiroi.SimaQian.MerkleTest do
  @moduledoc "The root is a function of the bytes and their paths alone (spec §6.10)."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Oneiroi.SimaQian.Merkle

  setup do
    dir = Path.join(System.tmp_dir!(), "oneiroi-merkle-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write!(dir, files) do
    for {path, body} <- files do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, body)
    end
  end

  test "an empty tree hashes to the hash of nothing", %{dir: dir} do
    assert Merkle.root(dir) == :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)
  end

  test "the same files in any order give the same root, and a byte or a path changes it", %{
    dir: dir
  } do
    files = [{"events/a.jsonl", "1\n"}, {"events/b.jsonl", "2\n"}, {"README.md", "r\n"}]
    write!(dir, files)
    root = Merkle.root(dir)

    other = Path.join(dir, "other")
    write!(other, Enum.reverse(files))
    assert Merkle.root(other) == root

    File.write!(Path.join(dir, "events/b.jsonl"), "3\n")
    changed = Merkle.root(dir)
    assert changed != root

    File.rename!(Path.join(dir, "events/b.jsonl"), Path.join(dir, "events/c.jsonl"))
    assert Merkle.root(dir) != changed
  end

  test "the leaves are in path order, each over the path, a NUL and the bytes", %{dir: dir} do
    write!(dir, [{"b", "x"}, {"a", "y"}])
    assert [{"a", a}, {"b", b}] = Merkle.leaves(dir)
    assert a == :crypto.hash(:sha256, "a" <> <<0>> <> "y")
    assert b == :crypto.hash(:sha256, "b" <> <<0>> <> "x")
    assert Merkle.root(dir) == :crypto.hash(:sha256, a <> b) |> Base.encode16(case: :lower)
  end

  property "any count of files, odd or even, reduces to one root that a rewrite reproduces", %{
    dir: dir
  } do
    check all(count <- integer(1..9), seed <- integer(0..1_000_000), max_runs: 30) do
      files = for n <- 1..count, do: {"f#{n}", "#{seed}-#{n}"}
      sub = Path.join(dir, "p#{System.unique_integer([:positive])}")
      write!(sub, files)
      root = Merkle.root(sub)
      File.rm_rf!(sub)
      write!(sub, Enum.shuffle(files))
      assert Merkle.root(sub) == root
      assert byte_size(root) == 64
    end
  end
end
