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
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    Model.clear()
    bare = tmp("bare")
    :ok = Git.init_bare(bare)
    created = [bare]
    on_exit(fn -> Enum.each(created, &File.rm_rf!/1) end)
    {:ok, witness: witness, actor: actor, bare: bare}
  end

  defp tmp(name),
    do: Path.join(System.tmp_dir!(), "oneiroi-#{name}-#{System.unique_integer([:positive])}")

  # 104 characters, the length of the name the rehearsal left behind.
  @long String.duplicate("a", 101) <> ".md"

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
    # The two of Lily's left behind on the rehearsal of 2026-10-31: a
    # name over the old bound of 100, adopted now, and a file under a
    # hidden folder that adoption never listed, left behind and named.
    File.mkdir_p!(Path.join(work, "wiki/sources"))
    File.write!(Path.join(work, "wiki/sources/#{@long}"), "# A long name\n\nKept.")
    File.mkdir_p!(Path.join(work, "wiki/lily/.openclaw-wiki"))
    File.write!(Path.join(work, "wiki/lily/.openclaw-wiki/log.jsonl"), "{}")
    File.mkdir_p!(Path.join(work, "transcripts"))
    File.write!(Path.join(work, "transcripts/2026-10-20.md"), "a transcript file")
    File.mkdir_p!(Path.join(work, "memory"))
    File.write!(Path.join(work, "memory/index.json"), "{}")
    # David's own records and Honcho files, as Lily's repository holds
    # them: not an Oneiroi export. The records are translated
    # (sima-qian #19, and SimaQian.DavidTest for the whole of it); a
    # file under them nothing reads, and the Honcho files, are named
    # rather than passed over.
    File.mkdir_p!(Path.join(work, "records/transcripts/2026/10"))

    File.write!(
      Path.join(work, "records/transcripts/2026/10/2026-10-20.jsonl"),
      ~s({"sentAt":"2026-10-20T10:00:00.000Z","agentId":"lily","sessionKey":"agent:lily:main","runKind":"user","role":"user","content":"Good morning."}\n) <>
        ~s({"sentAt":"2026-10-20T10:00:05.000Z","agentId":"lily","sessionKey":"agent:lily:main","runKind":"user","role":"assistant","content":"Morning."}\n)
    )

    File.write!(
      Path.join(work, "records/bookmarks.jsonl"),
      ~s({"id":1,"line":"the first morning","summary":"We said good morning.","sessionKey":"agent:lily:main","spanStart":"2026-10-20T10:00:00.000Z","spanEnd":"2026-10-20T10:00:05.000Z","pinnedBy":null,"pinnedAt":null,"createdAt":"2026-10-20T10:01:00.000Z","tags":[]}\n)
    )

    File.write!(Path.join(work, "records/README.md"), "David's own description of these files.")
    File.mkdir_p!(Path.join(work, "honcho"))
    File.write!(Path.join(work, "honcho/lily-peer-card.md"), "a card")
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
              adopted: 3,
              indexed: true,
              not_transferred: [
                "README.md",
                "honcho",
                "memory",
                "records/README.md",
                "transcripts",
                "wiki/lily/.openclaw-wiki/log.jsonl",
                "wiki/odd name/page.md"
              ],
              reasons: reasons,
              unaccounted: []
            }} =
             SimaQian.import_resident(
               url,
               %{name: "Lily", slug: "lily-moved"},
               ctx.witness.id,
               ctx.actor
             )

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)

    # Every one left behind says why (sima-qian #22).
    assert reasons == %{
             "README.md" => "a file at the root that is not an identity file",
             "honcho" => "outside the folders the library holds",
             # The library holds memory, as originals at a pinned commit
             # (seshat #28), and the reason says so rather than that it
             # cannot.
             "memory" =>
               "the originals of memory come in through the originals import, at a commit the witness pins, never with the repository",
             "records/README.md" => "a record nothing here reads",
             "transcripts" => "outside the folders the library holds",
             "wiki/lily/.openclaw-wiki/log.jsonl" =>
               "a hidden name, which the library does not hold",
             "wiki/odd name/page.md" =>
               "a name with characters other than letters, digits, dot, dash and underscore"
           }

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
                "honcho",
                "memory",
                "records/README.md",
                "transcripts",
                "wiki/lily/.openclaw-wiki/log.jsonl",
                "wiki/odd name/page.md"
              ],
              import_reasons: %{"wiki/lily/.openclaw-wiki/log.jsonl" => _},
              import_translated: %{
                "source" => "David",
                "counts" => %{"sessions" => 1, "messages" => 2, "bookmarks" => 1}
              }
            }} = AgathosDaimon.fetch(id)

    assert custody == "account:" <> ctx.witness.id

    assert [
             %{name: "SOUL.md", origin: "uploaded", content: "# Lily\n\n[soul/1] I am Lily."},
             %{name: "USER.md"}
           ] = AgathosDaimon.files(id)

    assert [
             %{path: "wiki/bread.md", kind: "wiki", origin: "adopted"},
             %{path: "wiki/sources/" <> @long},
             %{path: "writing/essay.md", kind: "writing", chunks: 1}
           ] =
             Seshat.documents(id) |> Enum.sort_by(& &1.path)

    # The path the library cannot name is named as not transferred, and is
    # gone from the records: they hold what the platform holds.
    assert Seshat.unadopted(id) == []
    assert {:ok, [%{path: "wiki/bread.md"} | _]} = Seshat.search(id, "flour and water", ctx.actor)

    # The records hold what the platform holds, under a history of their
    # own: the source's history and everything left behind are gone, and
    # the source repository still has them (2026-11-01: Lily's first
    # backup was refused for pushing her CI workflow, a file the import
    # had named as left behind).
    dir = Backup.dir(id)
    assert File.regular?(Path.join(dir, "writing/essay.md"))
    assert File.regular?(Path.join(dir, "wiki/bread.md"))
    assert File.regular?(Path.join(dir, "SOUL.md"))
    for name <- Map.keys(reasons), do: refute(File.exists?(Path.join(dir, name)), name)
    refute Git.head?(dir)

    # The same repository again is refused: an import is never a fork.
    assert {:error, %Oneiroi.SimaQian.Error{kind: :sima_qian_already_imported}} =
             SimaQian.import_resident(
               url,
               %{name: "Lily", slug: "lily-again"},
               ctx.witness.id,
               ctx.actor
             )

    # Told where it woke on the first turn, as a system message, once.
    {:ok, key} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)
    Honcho.clear(for: id)
    on_exit(fn -> Model.clear(for: id) end)

    assert {:ok,
            %{messages: [%{role: :system, content: notice}, %{role: :user}, %{role: :assistant}]}} =
             Oneiroi.Brain.turn(id, key, "hello", ctx.actor)

    assert notice =~ "You woke on Oneiroi"
    assert notice =~ url
    assert notice =~ "no attestation to check"
    assert notice =~ "did not transfer"

    for {name, reason} <- reasons, do: assert(notice =~ "#{name} (#{reason})")

    assert notice =~
             "From David's records, made into this platform's own: 1 conversations, as sessions of kind imported, searchable as any transcript; 2 messages in them; 1 bookmarks"

    assert {:ok, %{import_told: true}} = AgathosDaimon.fetch(id)

    assert {:ok, %{messages: [%{role: :user}, %{role: :assistant}]}} =
             Oneiroi.Brain.turn(id, key, "still here", ctx.actor)

    # The first backup starts the history, class by class, and strays on nothing.
    Clock.Fake.advance(120)
    assert {:ok, %{commits: commits}} = SimaQian.backup(id, ctx.actor)
    assert Enum.map(commits, &elem(&1, 0)) == ["soul", "writing", "machine"]
    log = git!(dir, ["log", "--format=%s"])
    refute log =~ "Lily's repository"
    assert log |> String.split("\n") |> Enum.all?(&String.starts_with?(&1, "Records: "))
  end

  test "a resident imported whole before the records started fresh is made fresh once, at its first backup",
       ctx do
    lily_repo!(ctx.bare)

    assert {:ok, %{id: id, reasons: reasons}} =
             SimaQian.import_resident(
               "file://" <> ctx.bare,
               %{name: "Lily", slug: "lily-whole"},
               ctx.witness.id,
               ctx.actor
             )

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)

    # Lily's shape on 2026-11-01: the source's commit and a file it had
    # named as left behind, and on top of them the commit her first
    # backup made before its push was refused, carrying our trailer.
    dir = Backup.dir(id)
    File.write!(Path.join(dir, "README.md"), "Lily's readme\n")
    git!(dir, ["add", "-A"])
    git!(dir, ["commit", "-q", "-m", "Lily's repository"])
    File.write!(Path.join(dir, "writing/night.md"), "# Night\n")
    git!(dir, ["add", "-A"])

    git!(dir, [
      "commit",
      "-q",
      "-m",
      "Records: machine through sequence 3\n\nOneiroi-Sequence: 3\nOneiroi-Root: x"
    ])

    assert Map.has_key?(reasons, "README.md")
    assert Map.has_key?(Git.head_trailers(dir), "Oneiroi-Sequence")

    remote = tmp("fresh-remote")
    :ok = Git.init_bare(remote)
    on_exit(fn -> File.rm_rf!(remote) end)
    :ok = SimaQian.set_remote(id, remote, nil, ctx.actor)
    Clock.Fake.advance(120)

    assert {:ok, %{commits: [_ | _]}} = SimaQian.backup(id, ctx.actor)
    refute File.exists?(Path.join(dir, "README.md"))
    pushed = git!(remote, ["log", "--format=%s", "main"])
    refute pushed =~ "Lily's repository"

    refute "README.md" in String.split(
             git!(remote, ["ls-tree", "-r", "--name-only", "main"]),
             "\n"
           )

    # Ours now: a later backup builds on it and resets nothing.
    first = git!(remote, ["rev-list", "--max-parents=0", "main"])
    File.write!(Path.join(dir, "writing/later.md"), "# Later\n")
    # `posts/` is a library folder, so a published post is held, not stray.
    File.mkdir_p!(Path.join(dir, "posts"))
    File.write!(Path.join(dir, "posts/hello.md"), "# Hello\n")
    Clock.Fake.advance(120)
    assert {:ok, _} = SimaQian.backup(id, ctx.actor)
    assert git!(remote, ["rev-list", "--max-parents=0", "main"]) == first
  end

  test "a first backup that committed and failed to push keeps its commits for the retry",
       ctx do
    lily_repo!(ctx.bare)

    assert {:ok, %{id: id}} =
             SimaQian.import_resident(
               "file://" <> ctx.bare,
               %{name: "Lily", slug: "lily-retry"},
               ctx.witness.id,
               ctx.actor
             )

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)
    dir = Backup.dir(id)

    # Lily's first night: the commits land, the push is refused.
    :ok = SimaQian.set_remote(id, "/nonexistent/oneiroi-remote.git", nil, ctx.actor)
    Clock.Fake.advance(120)
    assert {:error, %{kind: :sima_qian_git_failed}} = SimaQian.backup(id, ctx.actor)
    root = git!(dir, ["rev-list", "--max-parents=0", "HEAD"])

    # The retry pushes the history it made; its own is never started over.
    remote = tmp("retry-remote")
    :ok = Git.init_bare(remote)
    on_exit(fn -> File.rm_rf!(remote) end)
    :ok = SimaQian.set_remote(id, remote, nil, ctx.actor)
    Clock.Fake.advance(120)
    assert {:ok, _} = SimaQian.backup(id, ctx.actor)
    assert git!(remote, ["rev-list", "--max-parents=0", "main"]) == root
  end

  test "a records directory without its own .git is never reset from a repository above it",
       ctx do
    lily_repo!(ctx.bare)

    assert {:ok, %{id: id}} =
             SimaQian.import_resident(
               "file://" <> ctx.bare,
               %{name: "Lily", slug: "lily-bare-dir"},
               ctx.witness.id,
               ctx.actor
             )

    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)

    # The suite's records root sits inside this project's own repository,
    # so git run here without a `.git` reads the project's head: a reset
    # trusting it would empty the directory of anything outside the classes.
    dir = Backup.dir(id)
    File.rm_rf!(Path.join(dir, ".git"))
    File.write!(Path.join(dir, "stray.txt"), "left by hand\n")
    Clock.Fake.advance(120)

    assert {:error, %{kind: :sima_qian_stray_files}} = SimaQian.backup(id, ctx.actor)
    assert File.exists?(Path.join(dir, "stray.txt"))
  end

  test "a repository with records replays them, and a root file differing from them after first contact is proposed, not written",
       ctx do
    b = Fixtures.account!()
    r = Fixtures.resident!(b)
    b_actor = Actor.new(:witness, b.id)

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
             SimaQian.import_resident(url, %{}, ctx.witness.id, ctx.actor)

    assert events > 0
    on_exit(fn -> File.rm_rf!(Backup.dir(id)) end)
    refute id == r.id
    assert {:ok, %{slug: slug, custody: custody, import_told: false}} = AgathosDaimon.fetch(id)
    assert slug == r.slug <> "-" <> String.slice(id, 0, 8)
    assert custody == "account:" <> ctx.witness.id

    # The replayed stream carries the line events, so the rebuilt soul renders its markers.
    assert [%{name: "SOUL.md", content: "# Lily\n\n[soul/1] the seed", origin: "authored"}] =
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
               ctx.witness.id,
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
               ctx.witness.id,
               ctx.actor
             )

    lily_repo!(ctx.bare)

    assert {:error, %Oneiroi.SimaQian.Error{kind: :sima_qian_name_required}} =
             SimaQian.import_resident("file://" <> ctx.bare, %{}, ctx.witness.id, ctx.actor)

    assert Scope.platform(fn ->
             Store.imported(
               "file://" <> ctx.bare,
               Merkle.root(Path.join(ctx.bare, "nothing"))
             )
           end) == nil

    assert AgathosDaimon.for_witness(ctx.witness.id) == []
  end

  test "the source is recorded without its userinfo, where a GitHub URL carries the token" do
    assert Import.record_url("https://x-access-token:ghp_secret@github.com/a/lily.git") ==
             "https://github.com/a/lily.git"

    assert Import.record_url("/tmp/bare") == "/tmp/bare"
  end
end
