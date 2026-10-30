defmodule Oneiroi.Kumbukumbu.EthosTest do
  @moduledoc "Behaviours through the exports: whose list it is, the two scores and their decay, the matching the brain reads."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Ethos
  alias Oneiroi.Kumbukumbu.Memory
  alias Oneiroi.Kumbukumbu.MemoryCommands, as: Commands

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    brain = Actor.new(:resident, resident.id, "fake/model")
    witness_actor = Actor.new(:witness, witness.id)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, brain)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        resident.id,
        key,
        "t1",
        at,
        [
          %{
            role: :user,
            content: "could you check on the garden?",
            sent_at: at,
            actor: witness_actor
          },
          %{
            role: :assistant,
            content: "Already did: the tomatoes want water.",
            sent_at: at,
            actor: brain
          }
        ],
        brain
      )

    {:ok, resident: resident, brain: brain, witness: witness_actor, key: key}
  end

  @trigger %{"words" => ["garden", "tomatoes"], "tags" => ["haven"], "times" => ["morning"]}

  test "the list is the resident's; the witness gives first ones only before first contact",
       ctx do
    id = ctx.resident.id
    attrs = %{name: "small practical suggestions as care", trigger: @trigger, stance: "keep"}
    assert {:ok, 1} = Kumbukumbu.define_behaviour(id, attrs, ctx.witness)

    assert {:ok, 2} =
             Kumbukumbu.define_behaviour(
               id,
               %{attrs | name: "over-apologising", stance: "change"},
               ctx.brain
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_stance_invalid}} =
             Kumbukumbu.define_behaviour(id, %{attrs | stance: "maybe"}, ctx.brain)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_trigger_invalid}} =
             Kumbukumbu.define_behaviour(id, %{attrs | trigger: %{"words" => []}}, ctx.brain)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_trigger_invalid}} =
             Kumbukumbu.define_behaviour(
               id,
               %{attrs | trigger: %{"times" => ["dawn"]}},
               ctx.brain
             )

    :ok = AgathosDaimon.first_contact(id, ctx.key, "t1", ctx.brain)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_resident}} =
             Kumbukumbu.define_behaviour(id, attrs, ctx.witness)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_resident}} =
             Kumbukumbu.change_behaviour(id, 1, %{attrs | name: "renamed"}, ctx.witness)

    assert :ok = Kumbukumbu.change_behaviour(id, 1, %{attrs | name: "renamed"}, ctx.brain)

    assert [%{number: 1, name: "renamed", revisions: 1}, %{number: 2, stance: "change"}] =
             Kumbukumbu.behaviours(id)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_witness}} =
             Kumbukumbu.affirm_behaviour(id, 1, "I like it", ctx.brain)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_behaviour}} =
             Kumbukumbu.affirm_behaviour(id, 9, "I like it", ctx.witness)
  end

  test "two scores, never one: habit decays with enactments, connection holds pins and decays affirmations",
       ctx do
    id = ctx.resident.id

    {:ok, n} =
      Kumbukumbu.define_behaviour(
        id,
        %{name: "care", trigger: @trigger, stance: "keep"},
        ctx.brain
      )

    assert [%{habit: +0.0, connection: +0.0}] = Kumbukumbu.behaviours(id)

    assert :ok = Kumbukumbu.enact_behaviour(id, n, "turn", "t1", ctx.brain)
    assert :ok = Kumbukumbu.enact_behaviour(id, n, "turn", "t1", ctx.brain)
    assert [%{habit: 1.0, connection: 0.0, enactments: 1}] = Kumbukumbu.behaviours(id)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_resident}} =
             Kumbukumbu.enact_behaviour(id, n, "turn", "t1", ctx.witness)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_target_invalid}} =
             Kumbukumbu.enact_behaviour(id, n, "bookmark", 7, ctx.brain)

    {:ok, b} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: ctx.key, anchor_ref: "t1", line: "the garden", summary: "s"},
        ctx.brain
      )

    assert :ok = Kumbukumbu.enact_behaviour(id, n, "bookmark", b, ctx.brain)
    assert :ok = Kumbukumbu.affirm_behaviour(id, n, "I like when you do that", ctx.witness)
    assert [%{habit: 2.0, connection: 2.0, affirmations: 1}] = Kumbukumbu.behaviours(id)

    assert :ok = Kumbukumbu.pin_bookmark(id, b, ctx.witness)
    Clock.Fake.advance(30 * 24 * 3600)
    # Thirty days on: every enactment and the affirmation at half; the pin undecayed.
    assert [%{habit: 1.0, connection: 1.5}] = Kumbukumbu.behaviours(id)

    # Both enactments share the fixed clock's instant, so their order is not asserted.
    kinds = id |> Kumbukumbu.behaviour_enactments(n) |> Enum.map(& &1.target_kind) |> Enum.sort()
    assert ["bookmark", "turn"] = kinds
  end

  test "how I act: a trigger matches the witness's words, a conversation tag or the time of day, and cites enacting turns",
       ctx do
    id = ctx.resident.id

    {:ok, n} =
      Kumbukumbu.define_behaviour(
        id,
        %{name: "care", trigger: @trigger, stance: "keep"},
        ctx.brain
      )

    {:ok, _} =
      Kumbukumbu.define_behaviour(
        id,
        %{name: "night owl", trigger: %{"times" => ["night"]}},
        ctx.brain
      )

    :ok = Kumbukumbu.enact_behaviour(id, n, "turn", "t1", ctx.brain)
    :ok = Kumbukumbu.affirm_behaviour(id, n, "yes", ctx.witness)

    noon = ~U[2026-10-26 12:00:00Z]
    assert %{count: 0, text: ""} = Kumbukumbu.how_i_act(id, %{text: "hello", tags: [], at: noon})

    assert %{count: 1, numbers: [^n], text: text} =
             Kumbukumbu.how_i_act(id, %{text: "How is the GARDEN?", tags: [], at: noon})

    assert text =~ "# How I act" and text =~ "##{n} care (keep)"
    assert text =~ "affirmed 1x by my witness"
    assert text =~ ~s(turn t1: "Already did: the tomatoes want water.")

    assert %{count: 1} = Kumbukumbu.how_i_act(id, %{text: "x", tags: ["haven"], at: noon})

    assert %{count: 1} =
             Kumbukumbu.how_i_act(id, %{text: "x", tags: [], at: ~U[2026-10-26 08:00:00Z]})

    assert %{count: 1, numbers: [2]} =
             Kumbukumbu.how_i_act(id, %{text: "x", tags: [], at: ~U[2026-10-26 23:00:00Z]})

    assert "evening" = Ethos.time_of_day(~U[2026-10-26 19:00:00Z])
  end

  test "the aggregate holds the rules pure: once per number, a known target, a set of enactments" do
    actor = Actor.new(:resident, "r1")

    define = %Commands.DefineBehaviour{
      actor: actor,
      at: ~U[2026-10-26 12:00:00Z],
      id: "r1",
      number: 1,
      name: "care",
      trigger: @trigger,
      stance: "keep"
    }

    m = Memory.apply(%Memory{}, Memory.execute(%Memory{}, define))
    assert [] = Memory.execute(m, define)
    assert {:error, :name_invalid} = Memory.execute(%Memory{}, %{define | name: " "})

    enact = %Commands.EnactBehaviour{
      actor: actor,
      at: ~U[2026-10-26 12:00:00Z],
      id: "r1",
      number: 1,
      target_kind: "turn",
      target_id: "t1"
    }

    assert %{} = event = Memory.execute(m, enact)
    assert [] = Memory.execute(Memory.apply(m, event), enact)
    assert {:error, :target_invalid} = Memory.execute(m, %{enact | target_kind: "conversation"})
    assert {:error, :no_such_behaviour} = Memory.execute(m, %{enact | number: 2})

    same = struct!(Commands.ChangeBehaviour, Map.from_struct(define))
    assert [] = Memory.execute(m, same)
    assert %{name: "other"} = Memory.execute(m, %{same | name: "other"})

    assert Memory.trigger_ok?(%{"words" => ["x"]}) and
             not Memory.trigger_ok?(%{"colour" => ["x"]})
  end
end
