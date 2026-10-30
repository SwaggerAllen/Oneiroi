defmodule Oneiroi.SimaQian.RebuildTest do
  @moduledoc "Rebuild is replay: a new resident whose export is the source's, line for line (spec §6.10, §9)."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git

  setup do
    a = Fixtures.account!()
    b = Fixtures.account!()
    r = Fixtures.resident!(a)
    actor = Actor.new(:witness, a.id)
    {:ok, 1} = Oneiroi.AgathosDaimon.mint_id(r.id, "bookmark", actor)
    {:ok, 2} = Oneiroi.AgathosDaimon.mint_id(r.id, "bookmark", actor)
    bare = Path.join(System.tmp_dir!(), "oneiroi-bare-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    :ok = Oneiroi.SimaQian.set_remote(r.id, bare, nil, actor)
    Clock.Fake.advance(120)
    {:ok, %{root: root}} = Oneiroi.SimaQian.backup(r.id, actor)
    out = Path.join(System.tmp_dir!(), "oneiroi-rebuilt-#{System.unique_integer([:positive])}")
    created = [Backup.dir(r.id), bare, out]
    on_exit(fn -> Enum.each(created, &File.rm_rf!/1) end)
    {:ok, r: r, a: a, b: b, actor: actor, bare: bare, root: root, out: out}
  end

  defp lines(dir),
    do:
      dir
      |> Path.join("records/events/2026-10-26.jsonl")
      |> File.read!()
      |> String.split("\n", trim: true)

  test "the rebuilt resident is new, placed with the importing witness, and re-exports the same lines plus its own",
       %{
         r: r,
         b: b,
         bare: bare,
         root: root,
         out: out
       } do
    importer = Actor.new(:witness, b.id)

    assert {:ok, %{id: id, attestation: :held, root: ^root, events: 4, not_transferred: []}} =
             Oneiroi.SimaQian.rebuild(bare, b.id, importer)

    refute id == r.id
    row = Scope.platform(fn -> Store.get(id) end)
    assert row.account_id == b.id
    assert row.custody == "account:" <> b.id
    assert row.slug == r.slug <> "-" <> String.slice(id, 0, 8)
    assert row.import_source == bare
    assert row.import_root == root
    assert row.remote_url == nil
    assert row.last_backup_root == nil
    assert [^id] = Enum.map(Oneiroi.AgathosDaimon.for_witness(b.id), & &1.id)

    Clock.Fake.advance(120)
    assert {:ok, %{through: 6}} = Export.write(id, out)
    source = lines(Backup.dir(r.id))
    rebuilt = lines(out)
    assert Enum.take(rebuilt, length(source)) == source

    assert [imported, custody] =
             rebuilt |> Enum.drop(length(source)) |> Enum.map(&Jason.decode!/1)

    assert imported["type"] == "Oneiroi.AgathosDaimon.Events.Imported"
    assert imported["sequence"] == 5

    assert imported["data"] == %{
             "attestation" => "held",
             "id" => "$self",
             "root" => root,
             "sequence" => 4,
             "source" => bare
           }

    assert custody["type"] == "Oneiroi.AgathosDaimon.Events.CustodyTransferred"
    assert custody["data"]["to"] == "account:" <> b.id
    assert custody["data"]["note"] =~ "importing witness"
    refute Enum.any?(rebuilt, &(&1 =~ id))
  end

  test "a repository already rebuilt at that root is refused: an import is never a fork", %{
    b: b,
    bare: bare
  } do
    importer = Actor.new(:witness, b.id)
    assert {:ok, %{id: first}} = Oneiroi.SimaQian.rebuild(bare, b.id, importer)

    assert {:error, %Oneiroi.SimaQian.Error{kind: :sima_qian_already_imported}} =
             Oneiroi.SimaQian.rebuild(bare, b.id, importer)

    on_exit(fn -> File.rm_rf!(Backup.dir(first)) end)
  end

  test "a tampered repository rebuilds with the attestation recorded as failed", %{
    b: b,
    bare: bare,
    root: root
  } do
    work = Path.join(System.tmp_dir!(), "oneiroi-tamper-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(work) end)
    {_, 0} = System.cmd("git", ["clone", "-q", bare, work], stderr_to_stdout: true)
    path = Path.join(work, "records/events/2026-10-26.jsonl")
    File.write!(path, File.read!(path) |> String.replace("bookmark", "forgery"))

    identity = ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]
    {_, 0} = System.cmd("git", ["add", "-A"], cd: work)

    {_, 0} =
      System.cmd(
        "git",
        identity ++
          ["commit", "-q", "-m", "forged\n\nOneiroi-Sequence: 4\nOneiroi-Root: #{root}\n"],
        cd: work
      )

    {_, 0} =
      System.cmd("git", ["push", "-q", "origin", "HEAD:main"], cd: work, stderr_to_stdout: true)

    importer = Actor.new(:witness, b.id)

    assert {:ok, %{id: id, attestation: :failed, root: actual}} =
             Oneiroi.SimaQian.rebuild(bare, b.id, importer)

    assert actual != root
    row = Scope.platform(fn -> Store.get(id) end)
    assert row.import_root == actual

    assert {:ok, events} = Oneiroi.EventStore.read_stream_forward("resident-" <> id)

    assert %Oneiroi.AgathosDaimon.Events.Imported{attestation: "failed", sequence: 4} =
             Enum.at(events, -2).data

    assert %Oneiroi.AgathosDaimon.Events.IdMinted{kind: "forgery"} = Enum.at(events, 1).data
  end
end
