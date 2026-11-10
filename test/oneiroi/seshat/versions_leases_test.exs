defmodule Oneiroi.Seshat.VersionsLeasesTest do
  @moduledoc "A document's versions, diff and restore (seshat#54), the witness's edit leases and the resident's wait on them (seshat#55), and reacts on documents (kumbukumbu#61)."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Reactions
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     dir: dir,
     account: witness,
     witness: Actor.new(:witness, witness.id),
     lily: Actor.new(:resident, resident.id, "fake/model")}
  end

  # The nightly backup's commit, in miniature: whatever is on disk.
  defp commit!(dir, message) do
    identity = ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]
    {_, 0} = System.cmd("git", ["add", "-A"], cd: dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", identity ++ ["commit", "-q", "-m", message],
        cd: dir,
        stderr_to_stdout: true
      )

    Clock.Fake.advance(60)
  end

  defp turn(ctx), do: %{resident_id: ctx.id, session_key: "k", turn_ref: "t", resident: ctx.lily}
  defp run(name, args, ctx), do: Tools.run(name, Jason.encode!(args), turn(ctx))
  defp hash(words), do: Seshat.Documents.hash(words)

  test "versions join the repository's commits to who wrote each, and an uncommitted overwrite is listed, not restorable",
       ctx do
    path = "writing/essay.md"
    {:ok, _} = Seshat.write(ctx.id, path, "one\ntwo\n", ctx.witness, note: "the first draft")
    commit!(ctx.dir, "writing")
    Clock.Fake.advance(60)
    {:ok, _} = Seshat.write(ctx.id, path, "one\nTWO\nthree\n", ctx.lily)
    Clock.Fake.advance(60)
    # Overwritten before any backup: its words are gone from everywhere.
    {:ok, _} = Seshat.write(ctx.id, path, "lost\n", ctx.lily)
    Clock.Fake.advance(60)
    {:ok, _} = Seshat.write(ctx.id, path, "one\nTWO\nfour\n", ctx.lily)

    assert {:ok, %{path: ^path, current: current, versions: [now, lost, second, first]}} =
             Seshat.versions(ctx.id, path)

    assert current == hash("one\nTWO\nfour\n")
    assert %{act: "written", current: true, restorable: true, commit: nil} = now
    assert %{version: lost_hash, restorable: false} = lost
    assert lost_hash == hash("lost\n")
    assert second.actor == %{kind: "resident", id: ctx.id}
    refute second.restorable

    assert %{
             note: "the first draft",
             restorable: true,
             commit: sha,
             actor: %{kind: "witness"}
           } = first

    assert is_binary(sha) and byte_size(sha) == 40

    # The records system's port: the commits of one path with their blobs.
    assert {:ok, [%{commit: ^sha, blob: blob, subject: "writing"}]} =
             Oneiroi.SimaQian.repository_history(ctx.id, path, 10)

    assert {:ok, "one\ntwo\n"} = Oneiroi.SimaQian.repository_blob(ctx.id, blob)

    assert {:ok, "one\ntwo\n"} = Seshat.version(ctx.id, path, first.version)

    assert {:error, %Seshat.Error{kind: :seshat_no_such_version}} =
             Seshat.version(ctx.id, path, lost.version)

    assert {:ok, %{added: 2, removed: 1, runs: runs, to: ^current}} =
             Seshat.version_diff(ctx.id, path, first.version, nil)

    assert [%{op: "eq", lines: ["one"]}, %{op: "del", lines: ["two"]}, %{op: "ins"} | _] = runs

    # A restore is the normal write, with a note naming the version.
    assert {:ok, %{written: %{changed: true}}} =
             Seshat.restore(ctx.id, path, first.version, "back to the start", ctx.witness)

    assert File.read!(Path.join(ctx.dir, path)) == "one\ntwo\n"
    assert {:ok, %{versions: [restored | _]}} = Seshat.versions(ctx.id, path)
    assert restored.version == first.version
    assert restored.note =~ "Restored the version #{String.slice(first.version, 0, 12)}"
    assert restored.note =~ "back to the start"
  end

  test "an identity file restores by direct write before first contact and as a proposal after",
       ctx do
    :ok = Oneiroi.AgathosDaimon.write_file(ctx.id, "SOUL.md", "# Soul\n\nfirst", %{}, ctx.witness)
    File.write!(Path.join(ctx.dir, "SOUL.md"), "# Soul\n\nfirst")
    commit!(ctx.dir, "soul")

    :ok =
      Oneiroi.AgathosDaimon.write_file(ctx.id, "SOUL.md", "# Soul\n\nsecond", %{}, ctx.witness)

    File.write!(Path.join(ctx.dir, "SOUL.md"), "# Soul\n\nsecond")
    commit!(ctx.dir, "soul")

    assert {:ok, %{versions: [latest, oldest]}} = Seshat.versions(ctx.id, "SOUL.md")
    assert %{act: "committed", actor: nil, note: "soul", current: true} = latest

    assert {:ok, %{written: _}} =
             Seshat.restore(ctx.id, "SOUL.md", oldest.version, nil, ctx.witness)

    assert {:ok, %{content: soul}} = Oneiroi.AgathosDaimon.file(ctx.id, "SOUL.md")
    assert soul =~ "first"

    :ok = Oneiroi.AgathosDaimon.first_contact(ctx.id, "k", "t1", Actor.platform())

    assert {:ok, %{proposed: ref}} =
             Seshat.restore(ctx.id, "SOUL.md", latest.version, "his", ctx.witness)

    assert [%{ref: ^ref}] = Oneiroi.AgathosDaimon.edit_proposals(ctx.id)
  end

  test "her write on a leased path waits, and takes the lease once idle, his draft kept", ctx do
    path = "writing/shared.md"
    {:ok, _} = Seshat.write(ctx.id, path, "base\n", ctx.lily)

    assert {:ok, %{state: "held", takeable: false}} =
             Seshat.acquire_lease(ctx.id, path, ctx.witness)

    other = Actor.new(:witness, Fixtures.account!().id)

    assert {:error, %Seshat.Error{kind: :seshat_lease_held}} =
             Seshat.acquire_lease(ctx.id, path, other)

    assert {:error, %Seshat.Error{kind: :seshat_lease_invalid}} =
             Seshat.acquire_lease(ctx.id, path, ctx.lily)

    assert run("library_read", %{path: path}, ctx) =~ "Your witness holds an edit lease"

    # Her write waits: nothing written, the wait recorded and shown.
    assert run("document_write", %{path: path, content: "hers\n"}, ctx) =~ "Not written yet"
    assert File.read!(Path.join(ctx.dir, path)) == "base\n"
    assert %{waiting_at: %DateTime{}, takeable: false} = Seshat.lease(ctx.id, path)

    assert {:ok, %{has_draft: true}} =
             Seshat.renew_lease(ctx.id, path, "his draft\n", ctx.witness)

    # Idle past the window: takeable, never revoked; her next write takes it.
    Clock.Fake.advance(Oneiroi.Config.fetch!(:seshat, :lease_idle_seconds))
    assert %{state: "held", takeable: true} = Seshat.lease(ctx.id, path)

    assert run("document_write", %{path: path, content: "hers\n"}, ctx) =~
             "his unsaved draft is kept at human/drafts/writing/shared-"

    assert File.read!(Path.join(ctx.dir, path)) == "hers\n"
    assert %{state: "taken", kept_at: kept} = Seshat.lease(ctx.id, path)
    assert File.read!(Path.join(ctx.dir, kept)) == "his draft\n"

    assert {:error, %Seshat.Error{kind: :seshat_lease_taken}} =
             Seshat.renew_lease(ctx.id, path, "more", ctx.witness)

    assert :ok = Seshat.release_lease(ctx.id, path, ctx.witness)
    assert Seshat.lease(ctx.id, path) == nil
    assert Seshat.leases(ctx.id) == []

    # His own write renews his lease, and a released one lets hers in.
    {:ok, _} = Seshat.acquire_lease(ctx.id, path, ctx.witness)
    Clock.Fake.advance(120)
    {:ok, _} = Seshat.write(ctx.id, path, "his saved\n", ctx.witness)
    assert %{renewed_at: renewed} = Seshat.lease(ctx.id, path)
    assert renewed == Clock.now()
    :ok = Seshat.release_lease(ctx.id, path, ctx.witness)
    assert run("document_write", %{path: path, content: "hers again\n"}, ctx) =~ "Written"
  end

  test "a react on a document records the version it held and is told her", ctx do
    {:ok, _} = Seshat.write(ctx.id, "writing/r.md", "words", ctx.lily)
    assert {:ok, n} = Seshat.react_document(ctx.id, "writing/r.md", "🌙", ctx.witness)

    assert [%{number: ^n, target_kind: "document", path: "writing/r.md", document_hash: h}] =
             Kumbukumbu.reacts(ctx.id, path: "writing/r.md")

    assert h == hash("words")

    assert {:error, %Seshat.Error{}} =
             Seshat.react_document(ctx.id, "writing/none.md", "🌙", ctx.witness)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_react_invalid}} =
             Kumbukumbu.react(
               ctx.id,
               %{"kind" => "document", "path" => "writing/r.md", "hash" => "nope"},
               "🌙",
               ctx.witness
             )

    assert {line, ^n} = Reactions.untold(ctx.id, "k")
    assert line =~ "the document writing/r.md"
  end
end
