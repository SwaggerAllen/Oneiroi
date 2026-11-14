defmodule Oneiroi.Kumbukumbu.DomainsTest do
  @moduledoc """
  Domains per message (P23-R1, kumbukumbu#72): one conversation holds
  business and recovery; a turn's domain is the one named on it or the
  conversation's current one, carried forward; retrieval names another
  domain's memory as a door and never shows it; her deliberate reach is
  never scoped; a wall is a contract term both agreed, and closes the
  door, never her reach (agathos-daimon#45).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Ethos
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    id = resident.id
    him = "account:" <> witness.id

    # One conversation, three turns: an untagged one in the common room,
    # one he names business, one he names recovery.
    capture! = fn ref, words ->
      at = Clock.now()

      :ok =
        Kumbukumbu.capture(
          id,
          key,
          ref,
          at,
          [
            %{role: :user, content: "about #{words}", sent_at: at, actor: actor},
            %{role: :assistant, content: words, sent_at: at, actor: brain}
          ],
          brain
        )
    end

    capture!.("t-common", "The garden wants water.")
    :ok = Kumbukumbu.tag_domain(id, key, "t-biz", nil, "business", actor)
    capture!.("t-biz", "The pitch deck goes out Friday.")
    :ok = Kumbukumbu.tag_domain(id, key, "t-rec", nil, "recovery", actor)
    capture!.("t-rec", "The meeting at noon, ninety days.")

    for {n, ref, line} <- [
          {1, "t-common", "the garden"},
          {2, "t-biz", "the pitch deck"},
          {3, "t-rec", "the meeting, ninety days"}
        ] do
      {:ok, ^n} =
        Kumbukumbu.add_bookmark(
          id,
          %{session_key: key, anchor_ref: ref, line: line, summary: line},
          brain
        )
    end

    Fake.clear()
    on_exit(fn -> Fake.clear(for: id) end)

    {:ok,
     witness: witness, id: id, actor: actor, brain: brain, key: key, him: him, capture!: capture!}
  end

  # The conversation moved to business: the next turn he names so.
  defp to_business(ctx, ref \\ "t-now") do
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, ref, nil, "business", ctx.actor)
  end

  test "red: a session no longer opens with a domain; a domain is per message", ctx do
    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_domain_per_message}} =
             Kumbukumbu.open_session(ctx.id, "free_time", "brain", [ctx.witness.id], ctx.actor,
               domain: "intimate"
             )

    # A tag names a slug of someone's life, or nothing.
    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_domain_invalid}} =
             Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-x", nil, "Business!", ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_domain_invalid}} =
             Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-x", "him", "business", ctx.actor)
  end

  test "each turn lands in its named domain, and the last named carries forward to every untagged turn after it",
       ctx do
    by_turn = fn ->
      {:ok, _s, messages} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)
      Map.new(messages, &{&1.turn_ref, {&1.domain_person, &1.domain, &1.domain_tagged}})
    end

    him = ctx.him
    t = by_turn.()
    assert t["t-common"] == {nil, nil, false}
    assert t["t-biz"] == {him, "business", true}
    assert t["t-rec"] == {him, "recovery", true}
    assert %{person: ^him, domain: "recovery"} = Kumbukumbu.domain_now(ctx.id, ctx.key)

    # Untagged, incoming and outgoing alike: the current domain.
    ctx.capture!.("t-after", "Ninety-one.")
    assert by_turn.()["t-after"] == {him, "recovery", false}

    # Re-tagging an earlier turn carries forward until the next named one.
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-common", nil, "family", ctx.actor)
    t = by_turn.()
    assert t["t-common"] == {him, "family", true}
    assert t["t-biz"] == {him, "business", true}
    assert t["t-after"] == {him, "recovery", false}
    # The conversation stays in the last named.
    assert %{domain: "recovery"} = Kumbukumbu.domain_now(ctx.id, ctx.key)

    # Back to the common room.
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-plain", nil, nil, ctx.actor)
    assert Kumbukumbu.domain_now(ctx.id, ctx.key) == nil
  end

  test "green: a business turn is not given the recovery memory, is told of it as a door, and her reach opens it",
       ctx do
    id = ctx.id
    to_business(ctx)

    built = Kumbukumbu.index(id, ctx.key)
    assert Enum.sort(built.included) == [1, 2]
    assert built.doors == [3]
    refute built.text =~ "ninety days"

    assert built.text =~
             "Nearby in another domain: #3 (recovery). bookmark_open(number) opens one if you want it."

    assert [%{number: 3, reason: door}] = built.near_misses

    assert door ==
             "nearby: bookmark #3 (recovery), another domain; open it if you want it"

    # Her deliberate reach: never scoped.
    assert {:ok, %{number: 3}, [_ | _]} = Kumbukumbu.bookmark(id, 3)

    # The search keeps to business and the common room unless she crosses.
    assert [] = Kumbukumbu.search({:resident, id}, "ninety", 20, id, ctx.key)

    assert [%{turn_ref: "t-biz"} | _] =
             Kumbukumbu.search({:resident, id}, "pitch", 20, id, ctx.key)

    turn = %{
      resident_id: id,
      session_key: ctx.key,
      turn_ref: "t-now",
      started_at: Clock.now(),
      resident: ctx.brain
    }

    refute Tools.run("transcript_search", ~s({"q":"ninety","by":"phrase"}), turn) =~ "t-rec"

    assert Tools.run(
             "transcript_search",
             ~s({"q":"ninety","by":"phrase","across_domains":true}),
             turn
           ) =~ "t-rec"

    # A transcript read is never scoped.
    assert Tools.run("transcript_read", ~s({"session":"#{ctx.key}"}), turn) =~ "ninety days"

    # The madeleine never crosses uninvited.
    refute match?(
             %{bookmark: %{number: 3}},
             Kumbukumbu.madeleine(id, "the meeting, ninety days", ctx.brain, ctx.key)
           )

    # By meaning too: the recovery passage is never an answer in business,
    # and is with the deliberate cross.
    assert {:ok, %{messages: n}} = Kumbukumbu.refresh_passages(id, ctx.actor)
    assert n >= 3
    assert {:ok, near} = Kumbukumbu.search_meaning(id, ctx.key, "ninety days", 10, ctx.brain)
    refute Enum.any?(near, &(&1.turn_ref == "t-rec"))

    assert {:ok, across} =
             Kumbukumbu.search_meaning(id, ctx.key, "ninety days", 10, ctx.brain,
               across_domains: true
             )

    assert Enum.any?(across, &(&1.turn_ref == "t-rec"))
  end

  test "a wall is a contract term both agreed: the door closes, her reach stays whole", ctx do
    id = ctx.id
    to_business(ctx)

    wall = %{
      "memory" => %{"person" => ctx.him, "domain" => "recovery"},
      "context" => %{"person" => ctx.him, "domain" => "business"}
    }

    # A malformed wall is refused with the version.
    assert {:error, %{kind: :agathos_daimon_terms_invalid}} =
             AgathosDaimon.propose_contract(
               id,
               %{"domain_walls" => [%{"memory" => %{"domain" => "recovery"}}]},
               "",
               "a wall",
               ctx.actor
             )

    {:ok, v} =
      AgathosDaimon.propose_contract(id, %{"domain_walls" => [wall]}, "", "a wall", ctx.actor)

    # Proposed, not agreed: no wall stands on one party's word.
    assert Kumbukumbu.index(id, ctx.key).doors == [3]

    :ok = AgathosDaimon.agree_contract(id, v, "agreed", ctx.brain)
    assert [%{memory: %{domain: "recovery"}}] = AgathosDaimon.domain_walls(id)

    built = Kumbukumbu.index(id, ctx.key)
    assert built.doors == []
    refute built.text =~ "#3"
    assert built.near_misses == []

    # Her reach stays whole: the bookmark opens, the cross finds it.
    assert {:ok, %{number: 3}, _span} = Kumbukumbu.bookmark(id, 3)

    assert [3, 2, 1] ==
             Kumbukumbu.bookmark_page(id, ctx.key, across_domains: true).rows
             |> Enum.map(& &1.number)

    # The contract says the wall in words she reads.
    assert AgathosDaimon.contract_text(id) =~ "Domain walls: recovery"
  end

  test "the lane's exemplars: another domain's cited turn is a door, walled not even that", ctx do
    id = ctx.id
    to_business(ctx)
    noon = ~U[2026-10-26 12:00:00Z]

    {:ok, n} =
      Ethos.define_habit(
        id,
        %{name: "keeps count", trigger: %{"words" => ["count"]}, stance: "keep"},
        ctx.brain
      )

    :ok = Ethos.cite_habit(id, n, "turn", "t-rec", ctx.brain)
    :ok = Ethos.cite_habit(id, n, "turn", "t-biz", ctx.brain)
    situation = %{text: "shall we count?", tags: [], at: noon, session_key: ctx.key}

    assert %{text: text} = Ethos.how_i_act(id, situation)
    assert text =~ "turn t-biz: \"The pitch deck"
    assert text =~ "turn t-rec: nearby in another domain (recovery)"
    refute text =~ "ninety"
  end
end
