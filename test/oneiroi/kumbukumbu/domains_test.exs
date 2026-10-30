defmodule Oneiroi.Kumbukumbu.DomainsTest do
  @moduledoc "Memory domains (spec §6.3, P23): a session names its room, and the index, the search, the madeleine and the lane's exemplars respect it; a domain line approached is a near-miss."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
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

    {:ok, ikey} =
      Kumbukumbu.open_session(resident.id, "free_time", "brain", [witness.id], actor,
        domain: "intimate"
      )

    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        resident.id,
        key,
        "t-main",
        at,
        [%{role: :assistant, content: "The garden wants water.", sent_at: at, actor: brain}],
        brain
      )

    :ok =
      Kumbukumbu.capture(
        resident.id,
        ikey,
        "t-intimate",
        at,
        [
          %{
            role: :assistant,
            content: "The night we talked until late.",
            sent_at: at,
            actor: brain
          }
        ],
        brain
      )

    {:ok, 1} =
      Kumbukumbu.add_bookmark(
        resident.id,
        %{session_key: key, anchor_ref: "t-main", line: "the garden", summary: "watering"},
        brain
      )

    {:ok, 2} =
      Kumbukumbu.add_bookmark(
        resident.id,
        %{
          session_key: ikey,
          anchor_ref: "t-intimate",
          line: "the night we talked",
          summary: "late"
        },
        brain
      )

    Fake.clear()
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key, ikey: ikey}
  end

  test "a session names its room as a slug or not at all", ctx do
    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_domain_invalid}} =
             Kumbukumbu.open_session(ctx.id, "free_time", "brain", [ctx.witness.id], ctx.actor,
               domain: "Intimate!"
             )

    assert %{domain: nil, keys: [main]} = Kumbukumbu.room(ctx.id, ctx.key)
    assert main == ctx.key
    assert %{domain: "intimate", keys: keys} = Kumbukumbu.room(ctx.id, ctx.ikey)
    assert Enum.sort(keys) == Enum.sort([ctx.key, ctx.ikey])
    # A key no session has is the common room.
    assert %{domain: nil, keys: [^main]} = Kumbukumbu.room(ctx.id, "nothing")

    assert %{domain: "intimate"} =
             {:account, ctx.witness.id}
             |> Kumbukumbu.sessions()
             |> Enum.find(&(&1.key == ctx.ikey))
  end

  test "the index, the search and the madeleine respect the room, and the line approached is a near-miss",
       ctx do
    id = ctx.id

    # The common room sees the common room alone; the domain line approached is named.
    assert %{included: [1], near_misses: [miss]} = Kumbukumbu.index(id, ctx.key)
    assert %{number: 2, line: "the night we talked"} = miss

    assert miss.reason =~
             "held behind the domain line: a bookmark of the intimate domain ranked in"

    # The domain sees its own and the common room's, with nothing held.
    assert %{included: [2, 1], near_misses: []} = Kumbukumbu.index(id, ctx.ikey)
    # The unscoped index is every bookmark.
    assert %{included: [2, 1]} = Kumbukumbu.index(id)

    assert [] = Kumbukumbu.search({:resident, id}, "night", 20, id, ctx.key)

    assert [%{turn_ref: "t-intimate"}] =
             Kumbukumbu.search({:resident, id}, "night", 20, id, ctx.ikey)

    assert [%{turn_ref: "t-main"}] = Kumbukumbu.search({:resident, id}, "garden", 20, id, ctx.key)

    # The madeleine: the intimate bookmark sits nearest the words and is not surfaced in the common room.
    # In the common room the choice is a common-room bookmark or nothing, never the intimate one.
    refute match?(
             %{bookmark: %{number: 2}},
             Kumbukumbu.madeleine(id, "the night we talked", ctx.brain, ctx.key)
           )

    assert %{bookmark: %{number: 2}} =
             Kumbukumbu.madeleine(id, "the night we talked", ctx.brain, ctx.ikey)

    # The brain's turn in the common room: the index row leaves it out and
    # the near-miss row says why; the lane's exemplar and the search are
    # scoped by the turn's session.
    {:ok, n} =
      Ethos.define_habit(
        id,
        %{name: "waters", trigger: %{"words" => ["garden"]}, stance: "keep"},
        ctx.brain
      )

    :ok = Ethos.cite_habit(id, n, "turn", "t-intimate", ctx.brain)
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        if Enum.any?(messages, &(&1.role == :tool)) do
          {:ok, "Watered."}
        else
          send(test, {:request, messages})
          {:calls, [%{name: "transcript_search", arguments: %{q: "night"}}]}
        end
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref, messages: [_, searched, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "how is the garden?", ctx.actor)

    assert searched.content =~ "Nothing in the transcripts holds that."
    assert_received {:request, messages}

    acting =
      Enum.find(
        messages,
        &(&1.role == :system and String.starts_with?(&1.content, "# How I act"))
      )

    assert acting.content =~ "##{n} waters"
    refute acting.content =~ "t-intimate"

    rows = Kumbukumbu.injections({:account, ctx.witness.id}, ref)
    [index] = Enum.filter(rows, &(&1.label == "index"))
    refute index.text =~ "the night we talked"
    assert index.text =~ "the garden"

    assert [%{reason: reason}] = Enum.filter(rows, &(&1.label == "near-miss"))
    assert reason =~ "bookmark #2, held behind the domain line"
  end

  test "the lane's exemplars respect the room: a cited turn from another domain is not shown",
       ctx do
    id = ctx.id
    noon = ~U[2026-10-26 12:00:00Z]

    {:ok, n} =
      Ethos.define_habit(
        id,
        %{name: "stays up talking", trigger: %{"words" => ["talk"]}, stance: "keep"},
        ctx.brain
      )

    :ok = Ethos.cite_habit(id, n, "turn", "t-intimate", ctx.brain)
    :ok = Ethos.cite_habit(id, n, "turn", "t-main", ctx.brain)

    assert %{count: 1, text: common} =
             Ethos.how_i_act(id, %{
               text: "shall we talk?",
               tags: [],
               at: noon,
               session_key: ctx.key
             })

    assert common =~ "turn t-main"
    refute common =~ "t-intimate"

    assert %{count: 1, text: intimate} =
             Ethos.how_i_act(id, %{
               text: "shall we talk?",
               tags: [],
               at: noon,
               session_key: ctx.ikey
             })

    assert intimate =~ "t-intimate" and intimate =~ "t-main"

    # No session named: every cited turn may be shown.
    assert %{text: all} = Ethos.how_i_act(id, %{text: "shall we talk?", tags: [], at: noon})
    assert all =~ "t-intimate"
  end
end
