defmodule Oneiroi.SimaQian.ImportTest do
  @moduledoc "The intake from a repository (spec §6.2, §9): with or without records, the root seeded, the folders adopted, the rest named, and the resident told where it woke, once."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Import
  alias Oneiroi.SimaQian.Merkle

  @identity ["-c", "user.name=t", "-c", "user.email=t@example.invalid"]

  setup do
    steward = Fixtures.account!()
    actor = Actor.new(:steward, steward.id)
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", actor)
    Model.clear()
    bare = tmp("bare")
    :ok = Git.init_bare(bare)
    created = [bare]
    on_exit(fn -> Enum.each(created, &File.rm_rf!/1) end)
    {:ok, steward: steward, actor: actor, bare: bare}
  end

  defp tmp(name),
    do: Path.join(System.tmp_dir!(), "oneiroi-#{name}-#{System.unique_integer([:positive])}")

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", @identity ++ args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  # A repository shaped like Lily's, with no Oneiroi records in it.
  defp lily_repo!(bare) do
    work = tmp("lily")
    File.mkdir_p!(work)
    git!(work, ["init", "-q", "-b", "main"])
    File.write!(Path.join(work, "SOUL.md"), "# Lily\n\nI am Lily.")
    File.write!(Path.join(work, "USER.md"), "# David\n")
    File.write!(Path.join(work, "README.md"), "Lily's repository.")
    File.mkdir_p!(Path.join(work, "writing"))
    File.write!(Path.join(work, "writing/essay.md"), "# The essay\n\nOn bread, at length.")
    File.mkdir_p!(Path.join(work, "wiki"))
    File.write!(Path.join(work, "wiki/bread.md"), "# Bread\n\nFlour, water, salt, time.")
    File.mkdir_p!(Path.join(work, "wiki/odd name"))
    File.write!(Path.join(work, "wiki/odd name/page.md"), "a path the library cannot name")
    File.mkdir_p!(Path.join(work, "transcripts"))
    File.write!(Path.join(work, "transcripts/2026-10-20.md"), "a transcript file")
    File.mkdir_p!(Path.join(work, "memory"))
    File.write!(Path.join(work, "memory/index.json"), "{}")
    git!(work, ["add", "-A"])
    git!(work, ["commit", "-q", "-m", "Lily's repository"])
    :ok = Git.push(work, bare)
    File.rm_rf!(work)
    bare
  end

  test "a repository without records is a new resident: the root seeded, the folders adopted and indexed, the rest named, and told once",
       ctx do
    lily_repo!(ctx.bare)
    url = "file://" <> ctx.bare

    assert {:ok,
            %{
              id: id,
              attestation: :none,
              events: 0,
              seeded: ["SOUL.md", "USER.md"],
              proposed: [],
              adopted: 2,
              indexed: true,
              not_transferred: ["README.md", "memory", "transcripts", "wiki/odd name/page.md"]
            }} =
             SimaQian.import_resident(
               url,
               %{name: "Lily", slug: "lily-moved"},
               ctx.steward.id,
               ctx.actor
             )

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)

    assert {:ok,
            %{
              slug: "lily-moved",
              name: "Lily",
              custody: custody,
              import_source: ^url,
              import_attestation: "none",
              import_told: false,
              import_not_transferred: [
                "README.md",
                "memory",
                "transcripts",
                "wiki/odd name/page.md"
              ]
            }} = AgathosDaimon.fetch(id)

    assert custody == "account:" <> ctx.steward.id

    assert [
             %{name: "SOUL.md", origin: "uploaded", content: "# Lily\n\nI am Lily."},
             %{name: "USER.md"}
           ] = AgathosDaimon.files(id)

    assert [
             %{path: "wiki/bread.md", kind: "wiki", origin: "adopted"},
             %{path: "writing/essay.md", kind: "writing", chunks: 1}
           ] =
             Seshat.documents(id) |> Enum.sort_by(& &1.path)

    # The path the library cannot name stays on offer, and is named as not transferred.
    assert Seshat.unadopted(id) == ["wiki/odd name/page.md"]
    assert {:ok, [%{path: "wiki/bread.md"} | _]} = Seshat.search(id, "flour and water", ctx.actor)

    # The clone is the working repository, history and all, with no remote left in it.
    dir = Backup.dir(id)
    assert File.regular?(Path.join(dir, "writing/essay.md"))
    assert git!(dir, ["log", "--format=%s"]) == "Lily's repository"
    assert git!(dir, ["remote"]) == ""

    # The same repository again is refused: an import is never a fork.
    assert {:error, %Oneiroi.SimaQian.Error{kind: :sima_qian_already_imported}} =
             SimaQian.import_resident(
               url,
               %{name: "Lily", slug: "lily-again"},
               ctx.steward.id,
               ctx.actor
             )

    # Told where it woke on the first turn, as a system message, once.
    {:ok, key} = Kumbukumbu.main_session(id, ctx.steward.id, ctx.actor)
    Honcho.clear(for: id)
    on_exit(fn -> Model.clear(for: id) end)

    assert {:ok,
            %{messages: [%{role: :system, content: notice}, %{role: :user}, %{role: :assistant}]}} =
             Oneiroi.Brain.turn(id, key, "hello", ctx.actor)

    assert notice =~ "You woke on Oneiroi"
    assert notice =~ url
    assert notice =~ "no attestation to check"
    assert notice =~ "did not transfer"
    assert notice =~ "README.md, memory, transcripts, wiki/odd name/page.md"
    assert {:ok, %{import_told: true}} = AgathosDaimon.fetch(id)

    assert {:ok, %{messages: [%{role: :user}, %{role: :assistant}]}} =
             Oneiroi.Brain.turn(id, key, "still here", ctx.actor)

    # The next backup commits on top of the source's history and strays on nothing.
    Clock.Fake.advance(120)
    assert {:ok, %{commits: commits}} = SimaQian.backup(id, ctx.actor)
    assert Enum.map(commits, &elem(&1, 0)) == ["soul", "machine"]
    assert git!(dir, ["log", "--format=%s"]) =~ "Lily's repository"
  end

  test "a repository with records replays them, and a root file differing from them after first contact is proposed, not written",
       ctx do
    b = Fixtures.account!()
    r = Fixtures.resident!(b)
    b_actor = Actor.new(:steward, b.id)

    :ok =
      AgathosDaimon.write_file(
        r.id,
        "SOUL.md",
        "# Lily\n\nthe seed",
        %{origin: "authored"},
        b_actor
      )

    :ok = Oneiroi.Gaia.store_key(b.id, "sk-or-test", b_actor)
    {:ok, key} = Kumbukumbu.main_session(r.id, b.id, b_actor)
    Honcho.clear(for: r.id)
    assert {:ok, _} = Oneiroi.Brain.turn(r.id, key, "hello", b_actor)
    assert {:ok, %{first_contact_at: %DateTime{}}} = AgathosDaimon.fetch(r.id)
    :ok = SimaQian.set_remote(r.id, ctx.bare, nil, b_actor)
    Clock.Fake.advance(120)
    {:ok, %{root: _root}} = SimaQian.backup(r.id, b_actor)
    on_exit(fn -> File.rm_rf!(Backup.dir(r.id)) end)

    # A hand edit of the soul at the root after the last backup.
    work = tmp("edit")
    {_, 0} = System.cmd("git", ["clone", "-q", ctx.bare, work], stderr_to_stdout: true)
    File.write!(Path.join(work, "SOUL.md"), "# Lily\n\nedited by hand")
    git!(work, ["add", "-A"])
    git!(work, ["commit", "-q", "-m", "a hand edit"])
    git!(work, ["push", "-q", "origin", "HEAD:main"])
    File.rm_rf!(work)

    url = "file://" <> ctx.bare

    assert {:ok,
            %{
              id: id,
              attestation: :none,
              events: events,
              seeded: [],
              proposed: ["SOUL.md"],
              adopted: 0,
              not_transferred: []
            }} =
             SimaQian.import_resident(url, %{}, ctx.steward.id, ctx.actor)

    assert events > 0
    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)
    refute id == r.id
    assert {:ok, %{slug: slug, custody: custody, import_told: false}} = AgathosDaimon.fetch(id)
    assert slug == r.slug <> "-" <> String.slice(id, 0, 8)
    assert custody == "account:" <> ctx.steward.id

    assert [%{name: "SOUL.md", content: "# Lily\n\nthe seed", origin: "authored"}] =
             AgathosDaimon.files(id)

    assert [%{file: "SOUL.md", content: "# Lily\n\nedited by hand", note: note}] =
             AgathosDaimon.edit_proposals(id)

    assert note =~ "differing from the records"
    assert {:ok, events_read} = Oneiroi.EventStore.read_stream_forward("resident-" <> id)

    assert %Oneiroi.AgathosDaimon.Events.ImportCompleted{seeded: [], adopted: 0} =
             List.last(events_read).data
  end

  test "a bare path or an unlisted scheme is refused before anything is cloned, and a repository without records needs a name",
       ctx do
    assert {:error, %Oneiroi.SimaQian.Error{kind: :sima_qian_scheme_refused}} =
             SimaQian.import_resident(
               ctx.bare,
               %{name: "Lily", slug: "lily-path"},
               ctx.steward.id,
               ctx.actor
             )

    assert {:error,
            %Oneiroi.SimaQian.Error{
              kind: :sima_qian_scheme_refused,
              details: [scheme: "http", schemes: ["https", "file"]]
            }} =
             SimaQian.import_resident(
               "http://example.invalid/x.git",
               %{name: "Lily", slug: "lily-http"},
               ctx.steward.id,
               ctx.actor
             )

    lily_repo!(ctx.bare)

    assert {:error, %Oneiroi.SimaQian.Error{kind: :sima_qian_name_required}} =
             SimaQian.import_resident("file://" <> ctx.bare, %{}, ctx.steward.id, ctx.actor)

    assert Scope.platform(fn ->
             Store.imported(
               "file://" <> ctx.bare,
               Merkle.root(Path.join(ctx.bare, "nothing"))
             )
           end) == nil

    assert AgathosDaimon.for_steward(ctx.steward.id) == []
  end

  test "the source is recorded without its userinfo, where a GitHub URL carries the token" do
    assert Import.record_url("https://x-access-token:ghp_secret@github.com/a/lily.git") ==
             "https://github.com/a/lily.git"

    assert Import.record_url("/tmp/bare") == "/tmp/bare"
  end
end
