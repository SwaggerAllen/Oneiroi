defmodule Oneiroi.Xenia.PresenceTest do
  @moduledoc """
  xenia#20 (the resident's design/influencer-mode.md, the witness's
  sign-off 2026-11-15): the follow list verified and masked, the cursor's
  traversal, the pass's random sizes under their caps, every interaction
  earned by a read, one per account per day, the review's three answers,
  a revision keeping its place, the jittered release and the reader's
  receipt.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NightPasses
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Xenia
  alias Oneiroi.Xenia.Presence
  alias Oneiroi.Xenia.Substack.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(&Fake.clear/0)

    {:ok,
     id: resident.id,
     witness: Actor.new(:witness, witness.id),
     her: Actor.new(:resident, resident.id, "fake/model"),
     job: Actor.new(:job, "xenia_presence"),
     hands: Actor.new(:hands, "reader")}
  end

  defp account(key, author \\ nil),
    do: %{
      key: key,
      name: String.capitalize(key),
      host: "https://#{key}.substack.com",
      publication_id: 1,
      author_id: author
    }

  defp item(key, account, ago_hours, likes, comments \\ 0, restacks \\ 0),
    do: %{
      key: key,
      kind: if(String.starts_with?(key, "p-"), do: "post", else: "note"),
      account: account,
      title: if(String.starts_with?(key, "p-"), do: "Title #{key}"),
      url: "https://#{account}.substack.com/p/#{key}",
      at: DateTime.add(Clock.now(), -ago_hours * 3600),
      likes: likes,
      comments: comments,
      restacks: restacks,
      excerpt: "About #{key}."
    }

  defp on!(ctx, accounts) do
    Fake.put_profile(42, accounts)
    :ok = Xenia.set_presence(ctx.id, true, "@AllenStrut", ctx.witness)
    count = length(accounts)
    {:ok, ^count} = Xenia.refresh_follows(ctx.id, ctx.witness)
  end

  test "the follow list is recorded only when it matches the profile's own count; the mask is dated and reasoned",
       ctx do
    :ok = Xenia.set_presence(ctx.id, false, "allenstrut", ctx.witness)
    Fake.put_profile(42, [account("seven"), account("grace")], 3)

    assert {:error, %{kind: :xenia_presence_unverified}} =
             Xenia.refresh_follows(ctx.id, ctx.witness)

    assert Xenia.presence_accounts(ctx.id) == []

    Fake.put_profile(42, [account("seven"), account("grace")])
    assert {:ok, 2} = Xenia.refresh_follows(ctx.id, ctx.witness)

    assert {:error, _} = Xenia.exclude_account(ctx.id, "grace", "", ctx.witness)

    assert {:error, %{kind: :xenia_not_allowed}} =
             Xenia.exclude_account(ctx.id, "grace", "Haven-era", ctx.her)

    :ok = Xenia.exclude_account(ctx.id, "grace", "Followed for Haven, not StrutCo", ctx.witness)

    assert [
             %{
               key: "grace",
               excluded: true,
               reason: "Followed for Haven, not StrutCo",
               excluded_at: %DateTime{}
             },
             %{key: "seven", excluded: false}
           ] =
             Xenia.presence_accounts(ctx.id)

    # Off, nothing is drawn.
    assert Xenia.draw_presence(ctx.id, "2026-11-15", ctx.job) == :off
  end

  test "the cursor picks up after the last account sampled and wraps" do
    accounts = for k <- ~w(a b c d), do: %{key: k}
    assert Presence.from_cursor(accounts, nil) |> Enum.map(& &1.key) == ~w(a b c d)
    assert Presence.from_cursor(accounts, "b") |> Enum.map(& &1.key) == ~w(c d a b)
    assert Presence.from_cursor(accounts, "d") |> Enum.map(& &1.key) == ~w(a b c d)
  end

  test "the cuts: the ranked cut off the top by likes, comments ×2, restacks ×3; the serendipity cut from below it" do
    pool =
      for n <- 1..40 do
        i = item("p-#{n}", "a", n, rem(n, 7), rem(n, 3), rem(n, 2))
        Map.put(i, :score, Presence.score(i))
      end

    for _ <- 1..20 do
      reads = Presence.cuts(pool)
      ranked = Enum.filter(reads, &(&1.cut == "ranked"))
      below = Enum.filter(reads, &(&1.cut == "serendipity"))
      assert length(ranked) in 1..4
      assert length(below) in 1..4

      top =
        pool |> Enum.sort_by(&{-&1.score, -DateTime.to_unix(&1.at)}) |> Enum.take(length(ranked))

      assert Enum.map(ranked, & &1.key) == Enum.map(top, & &1.key)
      assert MapSet.disjoint?(MapSet.new(ranked, & &1.key), MapSet.new(below, & &1.key))
    end
  end

  test "a pass, once a day; reads earn interactions; one per account per day; the cap", ctx do
    on!(ctx, [account("seven", 7), account("grace", 8)])
    seven = for n <- 1..20, do: item("p-7#{n}", "seven", n, 10 - rem(n, 10))
    grace = for n <- 1..20, do: item("c-8#{n}", "grace", n, 3)
    Fake.put_items("seven", seven)
    Fake.put_items("grace", grace)

    assert {:ok, %{pass: pass, reads: reads}} = Xenia.draw_presence(ctx.id, "2026-11-15", ctx.job)
    assert {:ok, %{pass: ^pass}} = Xenia.draw_presence(ctx.id, "2026-11-15", ctx.job)
    assert pass.cap >= 1 and length(reads) == pass.ranked + pass.serendipity
    assert pass.pool in [20, 40]
    # Every account's first sample reaches back the lookback, no further.
    assert Enum.all?(Fake.asked(), fn {_k, since} ->
             DateTime.diff(Clock.now(), since, :day) == 7
           end)

    [first | _] = reads

    assert {:error, %{kind: :xenia_presence_unread}} =
             Xenia.stage_interaction(ctx.id, %{item: first.item, kind: "like"}, ctx.her)

    assert {:error, %{kind: :xenia_presence_not_drawn}} =
             Xenia.stage_interaction(ctx.id, %{item: "p-999", kind: "like"}, ctx.her)

    assert {:ok, %{text: "The whole of " <> _}} = Xenia.presence_read(ctx.id, first.item, ctx.her)

    assert {:error, %{kind: :xenia_presence_invalid}} =
             Xenia.stage_interaction(
               ctx.id,
               %{item: first.item, kind: "comment", text: " "},
               ctx.her
             )

    assert {:ok, n} =
             Xenia.stage_interaction(
               ctx.id,
               %{item: first.item, kind: "comment", text: "This landed."},
               ctx.her
             )

    # A second item of the same account, read, is still refused today.
    same = Enum.find(reads, &(&1.account == first.account and &1.item != first.item))

    if same do
      {:ok, _} = Xenia.presence_read(ctx.id, same.item, ctx.her)

      assert {:error, %{kind: :xenia_presence_account_today}} =
               Xenia.stage_interaction(ctx.id, %{item: same.item, kind: "like"}, ctx.her)
    end

    assert [
             %{
               interaction: %{number: ^n, state: "staged", text: "This landed."},
               read: %{item: item}
             }
           ] =
             Xenia.presence_interactions(ctx.id, nil)

    assert item == first.item

    # The day's file in her repository.
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(ctx.id)

    page =
      File.read!(Path.join([dir, "feeds", "presence", "2026-11-15.md"]))

    assert page =~ "# Presence, 2026-11-15"
    assert page =~ "##{n} comment on #{first.item}"
  end

  test "the review: revise keeps its place, approve releases at a jittered instant, the reader's receipt",
       ctx do
    on!(ctx, [account("seven", 7)])
    Fake.put_items("seven", for(n <- 1..10, do: item("p-#{n}", "seven", n, n)))
    {:ok, %{reads: [r | _]}} = Xenia.draw_presence(ctx.id, "2026-11-15", ctx.job)
    {:ok, _} = Xenia.presence_read(ctx.id, r.item, ctx.her)

    {:ok, n} =
      Xenia.stage_interaction(ctx.id, %{item: r.item, kind: "comment", text: "Nice."}, ctx.her)

    assert {:error, %{kind: :xenia_not_allowed}} =
             Xenia.decide_interaction(ctx.id, n, "approve", nil, ctx.her)

    assert {:error, %{kind: :xenia_presence_invalid}} =
             Xenia.decide_interaction(ctx.id, n, "revise", " ", ctx.witness)

    :ok = Xenia.decide_interaction(ctx.id, n, "revise", "Say what landed.", ctx.witness)

    assert {:error, %{kind: :xenia_already_decided}} =
             Xenia.decide_interaction(ctx.id, n, "pass", nil, ctx.witness)

    {:ok, m} =
      Xenia.stage_interaction(
        ctx.id,
        %{kind: "comment", text: "The second half landed: the forest.", supersedes: n},
        ctx.her
      )

    assert [
             %{interaction: %{number: ^m, item: item, supersedes: ^n}},
             %{interaction: %{number: ^n, state: "superseded", superseded_by: ^m}}
           ] =
             Xenia.presence_interactions(ctx.id, nil)

    assert item == r.item

    :ok = Xenia.decide_interaction(ctx.id, m, "approve", nil, ctx.witness)
    [%{interaction: approved}] = Xenia.presence_interactions(ctx.id, ["approved"])
    wait = DateTime.diff(approved.release_at, Clock.now())
    assert wait >= 300 and wait <= 360 * 60

    # Not due before its release; due after it, with the origin it goes from.
    assert Xenia.presence_due(ctx.id) == []
    Clock.Fake.advance(360 * 60 + 1)

    assert [
             %{
               number: ^m,
               action: "comment",
               target: "post",
               host: "https://seven.substack.com",
               text: "The second half landed: the forest."
             }
           ] =
             Xenia.presence_due(ctx.id)

    assert [%{key: "presence-out", pending: [%{number: ^m}]}] =
             Enum.filter(Xenia.reader(ctx.id).routes, &(&1.key == "presence-out"))

    assert {:error, %{kind: :xenia_not_allowed}} = Xenia.interaction_sent(ctx.id, m, nil, ctx.her)
    :ok = Xenia.interaction_sent(ctx.id, m, "https://seven.substack.com/p/x/comment/1", ctx.hands)
    assert Xenia.presence_due(ctx.id) == []

    assert [%{interaction: %{state: "sent", url: "https://seven.substack.com/p/x/comment/1"}} | _] =
             Xenia.presence_interactions(ctx.id, nil)
  end

  test "the resident's tools read and stage; the pass note lists the reads and what came back for revision",
       ctx do
    on!(ctx, [account("seven", 7)])
    Fake.put_items("seven", [item("p-1", "seven", 2, 5), item("p-2", "seven", 3, 1)])
    Fake.put_text("p-1", "The whole post, every word.")

    assert {:ok, note} = NightPasses.note(ctx.id, "presence", "2026-11-15", 1)
    assert note =~ "the presence pass for 2026-11-15"
    assert note =~ ~s{- p-1 (ranked): "Title p-1" from seven, 5 likes}

    turn = %{
      resident_id: ctx.id,
      session_key: "k",
      turn_ref: "t",
      started_at: Clock.now(),
      resident: ctx.her,
      housekeeping?: true
    }

    assert Tools.run("presence_read", ~s({"item":"p-1"}), turn) =~ "The whole post, every word."

    assert Tools.run("presence_stage", ~s({"item":"p-1","kind":"like"}), turn) =~
             "Staged as interaction #1"
  end
end
