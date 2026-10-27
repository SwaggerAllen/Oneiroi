defmodule Oneiroi.SimaQian.BackupTest do
  @moduledoc "Export, commit by class with the trailers, push, attest (spec §6.10); git against a local bare remote."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Merkle

  setup do
    a = Fixtures.account!()
    r = Fixtures.resident!(a)
    actor = Actor.new(:steward, a.id)
    {:ok, 1} = Oneiroi.AgathosDaimon.mint_id(r.id, "bookmark", actor)
    bare = Path.join(System.tmp_dir!(), "oneiroi-bare-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    :ok = Oneiroi.SimaQian.set_remote(r.id, bare, nil, actor)
    working = Backup.dir(r.id)

    on_exit(fn ->
      File.rm_rf!(bare)
      File.rm_rf!(working)
    end)

    Clock.Fake.advance(120)
    {:ok, r: r, a: a, actor: actor, bare: bare, working: working}
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  defp row(id), do: Scope.platform(fn -> Store.get(id) end)

  test "a backup exports, commits the machine class with the trailers, pushes and records it", %{
    r: r,
    actor: actor,
    bare: bare,
    working: working
  } do
    assert {:ok, %{through: 3, root: root, commits: [{"machine", sha}]}} =
             Oneiroi.SimaQian.backup(r.id, actor)

    assert root == Merkle.root(Path.join(working, "records"))
    assert git!(bare, ["rev-parse", "main"]) == sha
    message = git!(bare, ["log", "-1", "--format=%B", "main"])
    assert message =~ "Records: machine through sequence 3"
    assert message =~ "Oneiroi-Sequence: 3"
    assert message =~ "Oneiroi-Root: #{root}"

    assert git!(bare, ["ls-tree", "--name-only", "-r", "main"]) =~
             "records/events/2026-10-26.jsonl"

    assert %{
             exported_through: 3,
             last_backup_sequence: 3,
             last_backup_root: ^root,
             last_backup_commit: ^sha
           } =
             row(r.id)
  end

  test "a night with nothing new makes no commit", %{r: r, actor: actor} do
    assert {:ok, %{commits: [{"machine", sha}]}} = Oneiroi.SimaQian.backup(r.id, actor)
    Clock.Fake.advance(120)
    # The bookkeeping of the first run is now under the watermark, so the
    # export runs through it and still writes nothing new.
    assert {:ok, %{through: 5, commits: []}} = Oneiroi.SimaQian.backup(r.id, actor)
    assert %{last_backup_commit: ^sha} = row(r.id)
  end

  test "a stray file fails the run after the backup has landed", %{
    r: r,
    actor: actor,
    bare: bare,
    working: working
  } do
    :ok = Git.ensure_repo(working)
    File.write!(Path.join(working, "notes.txt"), "by hand\n")

    assert {:error,
            %Oneiroi.SimaQian.Error{kind: :sima_qian_stray_files, details: [paths: ["notes.txt"]]}} =
             Oneiroi.SimaQian.backup(r.id, actor)

    assert git!(bare, ["log", "-1", "--format=%s", "main"]) ==
             "Records: machine through sequence 3"

    assert %{last_backup_sequence: 3} = row(r.id)
  end

  test "a resident without a remote is backed up locally and the nightly job skips it", %{
    a: a,
    actor: actor
  } do
    other = Fixtures.resident!(a)
    on_exit(fn -> File.rm_rf!(Backup.dir(other.id)) end)
    assert {:ok, %{commits: [{"machine", _}]}} = Oneiroi.SimaQian.backup(other.id, actor)
    refute other.id in Enum.map(Backup.residents_with_remote(), & &1.id)
  end

  test "attestation: none before a backup, held after, a mismatch once the bytes change", %{
    r: r,
    actor: actor,
    working: working
  } do
    assert {:ok, :none} = Oneiroi.SimaQian.attest(r.id, actor)

    assert {:ok, %{root: root, commits: [{"machine", sha}]}} =
             Oneiroi.SimaQian.backup(r.id, actor)

    assert {:ok, :held} = Oneiroi.SimaQian.attest(r.id, actor)

    path = Path.join(working, "records/events/2026-10-26.jsonl")
    File.write!(path, File.read!(path) <> "{\"forged\":true}\n")
    assert {:ok, :mismatch} = Oneiroi.SimaQian.attest(r.id, actor)

    assert {:ok, events} = Oneiroi.EventStore.read_stream_forward("resident-" <> r.id)

    assert %Oneiroi.AgathosDaimon.Events.RootMismatchDetected{
             expected_root: ^root,
             actual_root: actual,
             commit: ^sha
           } = List.last(events).data

    assert actual == Merkle.root(Path.join(working, "records"))
    assert actual != root
  end

  # git 2.43 strips the credential from its own message; the port's redaction
  # is the belt for a version that does not.
  test "a GitHub token rides the push URL and never an error", %{working: working} do
    url = Git.github_url("https://github.com/lily/records.git", "ghp_secret")
    assert url == "https://x-access-token:ghp_secret@github.com/lily/records.git"

    :ok = Git.ensure_repo(working)

    assert {:error, message} =
             Git.push(working, "https://x-access-token:ghp_secret@127.0.0.1:9/x.git")

    refute message =~ "ghp_secret"
  end
end
