defmodule Oneiroi.SimaQian.OriginalsTest do
  @moduledoc "The originals import (sima-qian #40, seshat #28): the memory files of a real local git repository, taken byte for byte at a pinned commit, verified against the tree's blobs, registered with their provenance, read-only after."
  use Oneiroi.DataCase, async: false

  alias Commanded.Event.Upcaster
  alias Commanded.Serialization.JsonDecoder
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Events.DocumentAdopted
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Originals

  @identity ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]

  # Commit 1 is the fork; commit 2 is the source carrying on after it.
  @day_one "# Day one\n\nThe ferry crossed at seven. Ünd the gulls — loud.\n"
  @day_one_later "# Day one\n\nRewritten after the fork.\n"

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    resident = Fixtures.resident!(witness)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = SimaQian.repository_dir(resident.id)
    Model.clear()
    work = tmp("source")
    {first, second} = source!(work)

    on_exit(fn ->
      File.rm_rf!(work)
      File.rm_rf!(dir)
      Model.clear(for: resident.id)
    end)

    {:ok,
     witness: witness,
     actor: actor,
     id: resident.id,
     key: key,
     dir: dir,
     work: work,
     source: "file://" <> work,
     first: first,
     second: second}
  end

  defp tmp(name),
    do: Path.join(System.tmp_dir!(), "oneiroi-#{name}-#{System.unique_integer([:positive])}")

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", @identity ++ args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  defp put!(work, path, content) do
    File.mkdir_p!(Path.dirname(Path.join(work, path)))
    File.write!(Path.join(work, path), content)
  end

  defp source!(work) do
    File.mkdir_p!(work)
    git!(work, ["init", "-q", "-b", "main"])
    put!(work, "memory/2026-01-01.md", @day_one)
    put!(work, "memory/2026-01-02.md", "# Day two\n\nQuiet.\n")
    put!(work, "memory/dreaming/weekly/2026-W01.md", "# Week one\n\nA dream of rivers.\n")
    put!(work, "memory/dreaming/sky.png", <<137, 80, 78, 71, 0, 1, 2>>)
    put!(work, "memory/.draft.md", "a hidden file")
    put!(work, "memory/notes.json", "{}")
    put!(work, "memory/sub/aside.md", "# Aside\n")
    put!(work, "MEMORY.md", "# Memory\n\nThe long-term file.\n")
    put!(work, "DREAMS.md", "# Dreams\n\nThe diary.\n")
    put!(work, "writing/essay.md", "# Essay\n")
    git!(work, ["add", "-A"])
    git!(work, ["commit", "-q", "-m", "the fork"])
    first = git!(work, ["rev-parse", "HEAD"])

    put!(work, "memory/2026-01-01.md", @day_one_later)
    put!(work, "memory/2026-01-03.md", "# Day three\n\nAfter the fork.\n")
    git!(work, ["add", "-A"])
    git!(work, ["commit", "-q", "-m", "after the fork"])
    {first, git!(work, ["rev-parse", "HEAD"])}
  end

  defp import!(ctx, extra \\ %{}),
    do:
      SimaQian.import_originals(
        ctx.id,
        Map.merge(%{source: ctx.source, commit: ctx.first}, extra),
        ctx.actor
      )

  defp turn(ctx) do
    %{
      resident_id: ctx.id,
      session_key: ctx.key,
      turn_ref: "t-live",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.id, "fake/model")
    }
  end

  @taken ~w(memory/2026-01-01.md memory/2026-01-02.md memory/DREAMS.md memory/MEMORY.md memory/dreaming/weekly/2026-W01.md)

  test "the import at the fork's commit takes that commit's bytes, not the head's, each verified against its blob and registered with where it came from",
       ctx do
    assert {:ok, result} = import!(ctx)

    assert Enum.sort(result.written) == @taken
    assert result.unchanged == []
    assert Enum.sort(result.adopted) == @taken
    assert result.indexed
    assert result.commit == ctx.first
    assert result.refused == %{}

    # The source's root files land under memory/ keeping their names.
    assert result.mapped["MEMORY.md"] == "memory/MEMORY.md"
    assert result.mapped["DREAMS.md"] == "memory/DREAMS.md"
    assert result.mapped["memory/2026-01-01.md"] == "memory/2026-01-01.md"

    # What was not taken says why.
    assert result.skipped == %{
             "memory/.draft.md" => "a hidden name, which the library does not hold",
             "memory/dreaming/sky.png" =>
               "not a text file (the library reads .md, .markdown and .txt)",
             "memory/notes.json" => "outside the set asked for",
             "memory/sub/aside.md" => "outside the set asked for"
           }

    # Commit 1's bytes, exactly; the head's day three is not there.
    assert File.read!(Path.join(ctx.dir, "memory/2026-01-01.md")) == @day_one
    refute File.exists?(Path.join(ctx.dir, "memory/2026-01-03.md"))
    refute File.exists?(Path.join(ctx.dir, "writing/essay.md"))

    # Each row carries the blob the copy was verified against: the tree's.
    docs = Map.new(Seshat.documents(ctx.id), &{&1.path, &1})

    for path <- @taken do
      original =
        if path in ~w(memory/MEMORY.md memory/DREAMS.md), do: Path.basename(path), else: path

      doc = docs[path]
      assert doc.kind == "memory"
      assert doc.origin == "adopted"
      assert doc.source_repo == ctx.source
      assert doc.source_commit == ctx.first
      assert doc.source_path == original
      assert doc.source_blob == git!(ctx.work, ["rev-parse", "#{ctx.first}:#{original}"])
    end

    # The resident reads the exact bytes, with the provenance on the header.
    short = String.slice(ctx.first, 0, 12)

    assert Tools.run("library_read", ~s({"path":"memory/2026-01-01.md"}), turn(ctx)) ==
             "memory/2026-01-01.md (memory, #{byte_size(@day_one)} bytes, imported from #{ctx.source}@#{short}:memory/2026-01-01.md), whole.\n" <>
               @day_one

    assert Tools.run("library_search", ~s({"q":"ferry gulls"}), turn(ctx)) =~
             "imported from #{ctx.source}@#{short}:"
  end

  test "a second run at the same commit changes nothing", ctx do
    assert {:ok, _} = import!(ctx)
    before = Seshat.documents(ctx.id)
    runs = Seshat.index_runs(ctx.id, 50)

    assert {:ok, again} = import!(ctx)
    assert again.written == []
    assert again.adopted == []
    assert Enum.sort(again.unchanged) == @taken
    assert Seshat.documents(ctx.id) == before
    assert Seshat.index_runs(ctx.id, 50) == runs
  end

  test "a file already in the repository with other bytes is refused and never overwritten",
       ctx do
    File.mkdir_p!(Path.join(ctx.dir, "memory"))
    File.write!(Path.join(ctx.dir, "memory/2026-01-02.md"), "something else\n")

    assert {:ok, result} = import!(ctx)

    assert result.refused == %{
             "memory/2026-01-02.md" =>
               "in the repository already with other bytes; not overwritten"
           }

    assert File.read!(Path.join(ctx.dir, "memory/2026-01-02.md")) == "something else\n"
    refute "memory/2026-01-02.md" in result.adopted
    assert "memory/2026-01-01.md" in result.adopted
  end

  test "a copy that does not match its blob adopts nothing, says which, and leaves nothing of the run",
       ctx do
    tamper = fn full, bytes ->
      if String.ends_with?(full, "memory/2026-01-02.md"),
        do: File.write(full, bytes <> "x"),
        else: File.write(full, bytes)
    end

    assert {:error,
            %SimaQian.Error{
              kind: :sima_qian_original_mismatch,
              details: [paths: ["memory/2026-01-02.md"]]
            }} =
             Originals.run(ctx.id, %{source: ctx.source, commit: ctx.first}, ctx.actor, tamper)

    assert Seshat.documents(ctx.id) == []
    assert Path.wildcard(Path.join(ctx.dir, "memory/**/*.md")) == []
  end

  test "memory is read-only: no document write lands there, and only the originals import registers one",
       ctx do
    brain = Actor.new(:resident, ctx.id, "fake/model")

    for actor <- [brain, ctx.actor] do
      assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
               Seshat.write(ctx.id, "memory/2026-01-09.md", "# Mine\n", actor)
    end

    # Not even the platform's own core write.
    assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
             Seshat.Documents.write(ctx.id, "memory/2026-01-09.md", "# Mine\n", ctx.actor,
               core: true
             )

    refute File.exists?(Path.join(ctx.dir, "memory/2026-01-09.md"))

    # A file put there by hand is neither offered nor adoptable without
    # its provenance.
    File.mkdir_p!(Path.join(ctx.dir, "memory"))
    File.write!(Path.join(ctx.dir, "memory/by-hand.md"), "# By hand\n")
    assert Seshat.unadopted(ctx.id) == []

    assert {:error, %Seshat.Error{kind: :seshat_originals_only}} =
             Seshat.adopt(ctx.id, "memory/by-hand.md", ctx.actor)

    assert Seshat.original_refusal("memory/by-hand.md") == nil
    assert Seshat.original_refusal("writing/x.md") == "outside the folders that take originals"

    # And the port registers only originals.
    assert {:error, %Seshat.Error{kind: :seshat_path_invalid}} =
             Seshat.adopt_originals(ctx.id, [%{path: "wiki/x.md", provenance: %{}}], ctx.actor)
  end

  test "the commit is named in full, the patterns stay inside the tree, and only the witness runs it",
       ctx do
    assert {:error, %SimaQian.Error{kind: :sima_qian_commit_invalid}} =
             import!(ctx, %{commit: "main"})

    assert {:error, %SimaQian.Error{kind: :sima_qian_commit_invalid}} =
             import!(ctx, %{commit: String.slice(ctx.first, 0, 12)})

    assert {:error, %SimaQian.Error{kind: :sima_qian_paths_invalid}} =
             import!(ctx, %{paths: ["../elsewhere/*"]})

    assert {:error, %SimaQian.Error{kind: :sima_qian_not_the_witness}} =
             SimaQian.import_originals(
               ctx.id,
               %{source: ctx.source, commit: ctx.first},
               Actor.new(:resident, ctx.id, "fake/model")
             )

    # The head's commit is a different read: day one as rewritten.
    assert {:ok, _} = import!(ctx, %{commit: ctx.second, paths: ["memory/2026-01-03.md"]})
    assert File.exists?(Path.join(ctx.dir, "memory/2026-01-03.md"))
  end

  # Version 2 added the provenance (seshat #28); a version 1 adoption
  # reads as carrying none, which is true of it.
  test "a DocumentAdopted of version 1 upcasts to no provenance" do
    v1 =
      JsonDecoder.decode(%DocumentAdopted{
        actor: %{"kind" => "witness", "id" => "w", "model" => nil},
        at: "2026-10-31T00:00:00.000000Z",
        id: "r",
        path: "wiki/a.md",
        kind: "wiki",
        hash: "h",
        bytes: 1
      })

    assert DocumentAdopted.__version__() == 2
    assert %{provenance: nil, path: "wiki/a.md"} = Upcaster.upcast(v1, %{})
  end
end
