defmodule Oneiroi.SimaQian.CutoverTest do
  @moduledoc """
  A succession's fork and cutover (sima-qian#67, #68, agathos-daimon#63):
  the fork is her raw events re-keyed, redacted fields and all; her
  token never resolves to it; the cutover keeps her former self in the
  backup, proven, then puts the fork's life back under her own id, her
  slug and her runtimes intact, what she lived meanwhile gone, the
  artifacts filed; and every resident table is either cleared or kept
  by name.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Repos

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    andrew = Actor.new(:witness, witness.id)
    her = Actor.new(:resident, resident.id, "fake/model")
    :ok = AgathosDaimon.write_file(resident.id, "SOUL.md", "# Soul\n\nCurious.", %{}, andrew)
    {:ok, token} = AgathosDaimon.register_adapter(resident.id, "claude-code", "brain", andrew)
    day = Oneiroi.Sunna.today(resident.id).day
    {:ok, _} = Seshat.journal_add(resident.id, day, "note", "Before the fork.", her)

    bare = Path.join(System.tmp_dir!(), "cutover-backup-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)

    on_exit(fn ->
      File.rm_rf!(bare)
      File.rm_rf!(SimaQian.Backup.dir(resident.id))
    end)

    {:ok,
     id: resident.id,
     slug: resident.slug,
     andrew: andrew,
     her: her,
     token: token,
     day: day,
     bare: bare}
  end

  defp texts(id, day), do: Seshat.journal_day(id, day).entries |> Enum.map(& &1.text)

  test "the fork is her, byte for byte; her token never resolves to it", ctx do
    {:ok, %{copy_id: copy}} = SimaQian.succession_fork(ctx.id, ctx.andrew)

    # Redacted from the export, kept by the fork: the adapter's hash.
    assert [%{adapter: "claude-code"}] = AgathosDaimon.adapters(copy)
    assert {:ok, %{resident_id: id}} = AgathosDaimon.authenticate_adapter(ctx.token)
    assert id == ctx.id

    mine = Export.events(ctx.id) |> Enum.map(& &1.event_type)
    theirs = Export.events(copy) |> Enum.map(& &1.event_type)
    assert theirs -- mine == ["Elixir.Oneiroi.AgathosDaimon.Events.ForkMarked"]
    assert texts(copy, ctx.day) == ["Before the fork."]
  end

  test "the cutover keeps her former self, then puts the fork's life back under her id", ctx do
    {:ok, %{copy_id: copy}} = SimaQian.succession_fork(ctx.id, ctx.andrew)

    # She lives on meanwhile; so does the copy.
    {:ok, _} = Seshat.journal_add(ctx.id, ctx.day, "note", "Hers, after the fork.", ctx.her)
    copy_actor = Actor.new(:resident, copy, "fake/next")

    {:ok, _} =
      Seshat.journal_add(copy, ctx.day, "note", "The copy's, after the fork.", copy_actor)

    {:ok, _} =
      Repos.write(
        {:resident, ctx.id},
        [{:put, "notes/hers.md", "Hers.", nil}],
        "hers",
        Repos.platform()
      )

    {:ok, _} =
      Repos.write(
        {:resident, copy},
        [{:put, "notes/copy.md", "The copy's.", nil}],
        "copy",
        Repos.platform()
      )

    plan = %{
      original: ctx.id,
      copy: copy,
      target: ctx.id,
      backup: %{url: ctx.bare, token: nil},
      artifacts: [{"succession/c0-1.md", "# C0\n\n- lily:SOUL.md"}]
    }

    assert {:ok, %{backup_commit: sha, events: n, commit: commit}} =
             SimaQian.succession_cutover(plan, ctx.andrew)

    assert n > 0 and is_binary(commit)

    # Settled as Janus settles: a strongly consistent dispatch on a stream
    # the cutover never touched comes after every transplanted event.
    _ = Fixtures.resident!(Fixtures.account!())

    # Her former self, proven in the backup, with what she lived meanwhile.
    proof = ctx.bare <> "-check"
    on_exit(fn -> File.rm_rf!(proof) end)
    :ok = Git.clone(ctx.bare, proof)
    assert Git.head(proof) == sha

    lines =
      Path.wildcard(Path.join([proof, "records", "events", "*.jsonl"]))
      |> Enum.map_join(&File.read!/1)

    assert lines =~ "Hers, after the fork."

    # Under her id now: the fork's life, never what she lived meanwhile.
    assert texts(ctx.id, ctx.day) == ["Before the fork.", "The copy's, after the fork."]
    assert {:ok, %{slug: slug, state: "active", fork_of: nil}} = AgathosDaimon.fetch(ctx.id)
    assert slug == ctx.slug
    assert {:ok, %{resident_id: id}} = AgathosDaimon.authenticate_adapter(ctx.token)
    assert id == ctx.id

    types = Export.events(ctx.id) |> Enum.map(& &1.event_type)
    refute "Elixir.Oneiroi.AgathosDaimon.Events.ForkMarked" in types

    # Her repository is the fork's, the artifacts filed; and she goes on.
    assert Repos.text({:resident, ctx.id}, "succession/c0-1.md") =~ "lily:SOUL.md"
    assert Repos.text({:resident, ctx.id}, "notes/copy.md") == "The copy's."
    assert Repos.text({:resident, ctx.id}, "notes/hers.md") == nil
    {:ok, _} = Seshat.journal_add(ctx.id, ctx.day, "note", "Going on.", ctx.her)
    assert List.last(texts(ctx.id, ctx.day)) == "Going on."
  end

  test "no backup proven, nothing replaced", ctx do
    {:ok, %{copy_id: copy}} = SimaQian.succession_fork(ctx.id, ctx.andrew)

    plan = %{
      original: ctx.id,
      copy: copy,
      target: ctx.id,
      backup: %{url: "/nowhere/#{System.unique_integer([:positive])}", token: nil},
      artifacts: []
    }

    assert {:error, _} = SimaQian.succession_cutover(plan, ctx.andrew)
    assert texts(ctx.id, ctx.day) == ["Before the fork."]
  end

  test "every resident table is cleared at a cutover or kept by name" do
    %{cleared: cleared, kept: kept} = SimaQian.cutover_tables()
    assert "seshat_journal_entry" in cleared and "agathos_daimon_resident" in cleared

    assert Enum.sort(kept) ==
             Enum.sort(
               ~w(gaia_household_resident gaia_witnessing kumbukumbu_house_letter seshat_lease xenia_profile
                  eunomia_regression_answer eunomia_regression_run eunomia_regression_test) ++
                 Enum.filter(kept, &String.starts_with?(&1, "janus_"))
             )
  end
end
