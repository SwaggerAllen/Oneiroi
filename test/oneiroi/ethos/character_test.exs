defmodule Oneiroi.Ethos.CharacterTest do
  @moduledoc "The character layer through the exports: whose habits they are, the two scores and their decay, the trigger lane the brain reads, the seedbed with its receipted graduations and the fork's confirmations, the aggregate's rules pure."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Ethos
  alias Oneiroi.Ethos.Character
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Habits
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat.Citations

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

  test "the list is the resident's; the witness gives first habits only before first contact",
       ctx do
    id = ctx.resident.id
    attrs = %{name: "small practical suggestions as care", trigger: @trigger, stance: "keep"}
    assert {:ok, 1} = Ethos.define_habit(id, attrs, ctx.witness)

    assert {:ok, 2} =
             Ethos.define_habit(
               id,
               %{attrs | name: "over-apologising", stance: "change"},
               ctx.brain
             )

    assert {:error, %Ethos.Error{kind: :ethos_stance_invalid}} =
             Ethos.define_habit(id, %{attrs | stance: "maybe"}, ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_trigger_invalid}} =
             Ethos.define_habit(id, %{attrs | trigger: %{"words" => []}}, ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_trigger_invalid}} =
             Ethos.define_habit(id, %{attrs | trigger: %{"times" => ["dawn"]}}, ctx.brain)

    :ok = AgathosDaimon.first_contact(id, ctx.key, "t1", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.define_habit(id, attrs, ctx.witness)

    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.change_habit(id, 1, %{attrs | name: "renamed"}, ctx.witness)

    assert :ok = Ethos.change_habit(id, 1, %{attrs | name: "renamed"}, ctx.brain)

    assert [%{number: 1, name: "renamed", revisions: 1}, %{number: 2, stance: "change"}] =
             Ethos.habits(id)

    assert {:error, %Ethos.Error{kind: :ethos_not_the_witness}} =
             Ethos.affirm_habit(id, 1, "I like it", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_no_such_habit}} =
             Ethos.affirm_habit(id, 9, "I like it", ctx.witness)

    # A habit is citeable by its number (seshat #14), resolved to its words.
    assert {:ok, "renamed (keep)"} =
             Citations.resolve(%{id: id, slug: ctx.resident.slug}, %{
               slug: ctx.resident.slug,
               kind: "habit",
               ref: "1"
             })
  end

  test "two scores, never one: habit decays with citations, connection holds pins and decays affirmations",
       ctx do
    id = ctx.resident.id

    {:ok, n} =
      Ethos.define_habit(id, %{name: "care", trigger: @trigger, stance: "keep"}, ctx.brain)

    assert [%{habit: +0.0, connection: +0.0}] = Ethos.habits(id)

    assert :ok = Ethos.cite_habit(id, n, "turn", "t1", ctx.brain)
    assert :ok = Ethos.cite_habit(id, n, "turn", "t1", ctx.brain)
    assert [%{habit: 1.0, connection: 0.0, citations: 1, days: 1}] = Ethos.habits(id)

    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.cite_habit(id, n, "turn", "t1", ctx.witness)

    assert {:error, %Ethos.Error{kind: :ethos_target_invalid}} =
             Ethos.cite_habit(id, n, "bookmark", 7, ctx.brain)

    {:ok, b} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: ctx.key, anchor_ref: "t1", line: "the garden", summary: "s"},
        ctx.brain
      )

    assert :ok = Ethos.cite_habit(id, n, "bookmark", b, ctx.brain)
    assert :ok = Ethos.affirm_habit(id, n, "I like when you do that", ctx.witness)
    assert [%{habit: 2.0, connection: 2.0, affirmations: 1}] = Ethos.habits(id)

    assert :ok = Kumbukumbu.pin_bookmark(id, b, ctx.witness)
    Clock.Fake.advance(30 * 24 * 3600)
    # Thirty days on: every citation and the affirmation at half; the pin undecayed.
    assert [%{habit: 1.0, connection: 1.5}] = Ethos.habits(id)

    # Both citations share the fixed clock's instant, so their order is not asserted.
    kinds = id |> Ethos.habit_citations(n) |> Enum.map(& &1.target_kind) |> Enum.sort()
    assert ["bookmark", "turn"] = kinds
  end

  test "how I act: the trigger lane matches the witness's words, a conversation tag or the time of day, cites turns, and counts the open seeds",
       ctx do
    id = ctx.resident.id

    {:ok, n} =
      Ethos.define_habit(id, %{name: "care", trigger: @trigger, stance: "keep"}, ctx.brain)

    {:ok, _} =
      Ethos.define_habit(id, %{name: "night owl", trigger: %{"times" => ["night"]}}, ctx.brain)

    :ok = Ethos.cite_habit(id, n, "turn", "t1", ctx.brain)
    :ok = Ethos.affirm_habit(id, n, "yes", ctx.witness)

    noon = ~U[2026-10-26 12:00:00Z]

    assert %{count: 0, text: "", seeds: 0} =
             Ethos.how_i_act(id, %{text: "hello", tags: [], at: noon})

    assert %{count: 1, numbers: [^n], text: text} =
             Ethos.how_i_act(id, %{text: "How is the GARDEN?", tags: [], at: noon})

    assert text =~ "# How I act" and text =~ "##{n} care (keep)"
    assert text =~ "cited 1x over 1 day"
    assert text =~ "affirmed 1x by my witness"
    assert text =~ ~s(turn t1: "Already did: the tomatoes want water.")
    refute text =~ "open seed"

    assert %{count: 1} = Ethos.how_i_act(id, %{text: "x", tags: ["haven"], at: noon})
    assert %{count: 1} = Ethos.how_i_act(id, %{text: "x", tags: [], at: ~U[2026-10-26 08:00:00Z]})

    assert %{count: 1, numbers: [2]} =
             Ethos.how_i_act(id, %{text: "x", tags: [], at: ~U[2026-10-26 23:00:00Z]})

    assert "evening" = Habits.time_of_day(~U[2026-10-26 19:00:00Z])

    # Open seeds are counted in the lane, never loaded.
    {:ok, _} = Ethos.plant_seed(id, "I might be becoming someone who rests.", ctx.brain)

    assert %{count: 0, seeds: 1, text: text} =
             Ethos.how_i_act(id, %{text: "hello", tags: [], at: noon})

    assert text =~ "1 open seed of who I might be becoming; seed_list reads them."
    refute text =~ "someone who rests"
  end

  test "the seedbed: planted by the resident alone, cited across days, graduated toward a habit only once confirmed, toward a position freely, wilted without ceremony; every move leaves the row",
       ctx do
    id = ctx.resident.id

    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.plant_seed(id, "x", ctx.witness)

    assert {:error, %Ethos.Error{kind: :ethos_seed_text_invalid}} =
             Ethos.plant_seed(id, "  ", ctx.brain)

    assert {:ok, 1} = Ethos.plant_seed(id, "I might be becoming someone who rests.", ctx.brain)
    assert {:ok, 2} = Ethos.plant_seed(id, "I think I like bread more than cake.", ctx.brain)
    assert [%{number: 1, state: "open", citations: 0, days: 0}, %{number: 2}] = Ethos.seeds(id)

    # The fork (research §3): one day of citations is a hypothesis.
    assert :ok = Ethos.cite_seed(id, 1, "turn", "t1", ctx.brain)
    assert :ok = Ethos.cite_seed(id, 1, "turn", "t1", ctx.brain)
    assert [%{number: 1, citations: 1, days: 1} | _] = Ethos.seeds(id)

    # A graduation is a decision: its note is required by the middleware.
    attrs = %{
      name: "rests",
      trigger: %{"times" => ["evening"]},
      stance: "keep",
      seed_number: 1,
      note: "it kept happening"
    }

    assert {:error, %Ethos.Error{kind: :ethos_unconfirmed, details: [days: 1, required: 2]}} =
             Ethos.define_habit(id, attrs, ctx.brain)

    assert [] = Ethos.habits(id)
    assert [%{number: 1, state: "open"} | _] = Ethos.seeds(id)

    Clock.Fake.advance(86_400)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        ctx.key,
        "t2",
        at,
        [%{role: :assistant, content: "Resting now.", sent_at: at, actor: ctx.brain}],
        ctx.brain
      )

    assert :ok = Ethos.cite_seed(id, 1, "turn", "t2", ctx.brain)
    assert [%{number: 1, citations: 2, days: 2} | _] = Ethos.seeds(id)

    # Confirmed across two days: the seed graduates into the habit it becomes, receipted.
    assert {:ok, habit} = Ethos.define_habit(id, attrs, ctx.brain)

    assert [%{number: ^habit, name: "rests", seed_number: 1}] = Ethos.habits(id)

    assert [
             %{
               number: 1,
               state: "graduated",
               graduated_to_kind: "habit",
               graduated_to_id: to_id,
               graduation_note: "it kept happening",
               citations: 2
             },
             %{number: 2, state: "open"}
           ] = Ethos.seeds(id)

    assert to_id == Integer.to_string(habit)

    # A closed seed is history: no more citations, no second graduation.
    assert {:error, %Ethos.Error{kind: :ethos_seed_closed}} =
             Ethos.cite_seed(id, 1, "turn", "t2", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_seed_closed}} =
             Ethos.wilt_seed(id, 1, ctx.brain)

    # An evaluative seed graduates toward a position with no citations asked.
    assert {:error, %Ethos.Error{kind: :ethos_graduation_invalid}} =
             Ethos.graduate_seed(id, 2, "mood", "x", "no", ctx.brain)

    # Toward a soul line the line must be live; toward a position nothing is checked here.
    assert {:error, %Ethos.Error{kind: :ethos_target_invalid}} =
             Ethos.graduate_seed(id, 2, "soul", 9, "a line of me", ctx.brain)

    assert :ok =
             Ethos.graduate_seed(id, 2, "position", 4, "a taste, not a disposition", ctx.brain)

    assert [_, %{number: 2, state: "graduated", graduated_to_kind: "position"}] = Ethos.seeds(id)

    # Wilting is the resident's, without a note, and the row stays.
    assert {:ok, 3} = Ethos.plant_seed(id, "maybe mornings", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_not_the_resident}} =
             Ethos.wilt_seed(id, 3, ctx.witness)

    assert :ok = Ethos.wilt_seed(id, 3, ctx.brain)
    assert [_, _, %{number: 3, state: "wilted", closed_at: %DateTime{}}] = Ethos.seeds(id)
    assert {:error, %Ethos.Error{kind: :ethos_no_such_seed}} = Ethos.wilt_seed(id, 9, ctx.brain)

    # Toward a soul line that is live, by its number (agathos-daimon #27).
    assert {:ok, 4} = Ethos.plant_seed(id, "I might be someone who waits.", ctx.brain)
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nI wait.", %{cites: [4]}, ctx.brain)
    assert :ok = Ethos.graduate_seed(id, 4, "soul", 1, "it is a line of me now", ctx.brain)

    assert [
             _,
             _,
             _,
             %{number: 4, state: "graduated", graduated_to_kind: "soul", graduated_to_id: "1"}
           ] =
             Ethos.seeds(id)

    assert [%{number: 1, text: "I wait.", cites: [4]}] = AgathosDaimon.soul_lines(id)

    # Citeable by number, with its state (seshat #14).
    assert {:ok, "maybe mornings (wilted)"} =
             Citations.resolve(%{id: id, slug: ctx.resident.slug}, %{
               slug: ctx.resident.slug,
               kind: "seed",
               ref: "3"
             })
  end

  test "the aggregate holds the rules pure: once per number, a known target, a set of citations, the fork's count of days" do
    actor = Actor.new(:resident, "r1")
    at = ~U[2026-10-26 12:00:00Z]

    define = %Commands.DefineHabit{
      actor: actor,
      at: at,
      id: "r1",
      number: 1,
      name: "care",
      trigger: @trigger,
      stance: "keep",
      seed_number: nil
    }

    s = Character.apply(%Character{}, Character.execute(%Character{}, define))
    assert [] = Character.execute(s, define)
    assert {:error, :name_invalid} = Character.execute(%Character{}, %{define | name: " "})

    cite = %Commands.CiteHabit{
      actor: actor,
      at: at,
      id: "r1",
      number: 1,
      target_kind: "turn",
      target_id: "t1"
    }

    assert %{} = event = Character.execute(s, cite)
    assert [] = Character.execute(Character.apply(s, event), cite)
    assert {:error, :target_invalid} = Character.execute(s, %{cite | target_kind: "conversation"})
    assert {:error, :no_such_habit} = Character.execute(s, %{cite | number: 2})

    same = struct!(Commands.ChangeHabit, Map.drop(Map.from_struct(define), [:seed_number]))
    assert [] = Character.execute(s, same)
    assert %{name: "other"} = Character.execute(s, %{same | name: "other"})

    assert Character.trigger_ok?(%{"words" => ["x"]}) and
             not Character.trigger_ok?(%{"colour" => ["x"]})

    # Seeds: the days are counted from the citations' instants, and the
    # required count is the command's.
    plant = %Commands.PlantSeed{actor: actor, at: at, id: "r1", number: 1, text: "becoming"}
    s = Character.apply(s, Character.execute(s, plant))

    seed_cite = %Commands.CiteSeed{
      actor: actor,
      at: at,
      id: "r1",
      number: 1,
      target_kind: "turn",
      target_id: "t1"
    }

    s = Character.apply(s, Character.execute(s, seed_cite))
    assert [] = Character.execute(s, seed_cite)
    next_day = %{seed_cite | at: ~U[2026-10-27 12:00:00Z], target_id: "t2"}
    s2 = Character.apply(s, Character.execute(s, next_day))

    graduate = %Commands.GraduateSeed{
      actor: actor,
      at: at,
      note: "n",
      id: "r1",
      number: 1,
      to_kind: "habit",
      to_id: "1",
      required: 2
    }

    assert {:error, {:unconfirmed, 1, 2}} = Character.execute(s, graduate)
    assert %{to_kind: "habit"} = Character.execute(s2, graduate)
    assert %{to_kind: "soul"} = Character.execute(s, %{graduate | to_kind: "soul", to_id: "7"})
    assert {:error, :graduation_invalid} = Character.execute(s, %{graduate | to_kind: "mood"})
    assert {:error, :no_such_seed} = Character.execute(s, %{graduate | number: 9})

    wilted =
      Character.apply(
        s,
        Character.execute(s, %Commands.WiltSeed{actor: actor, at: at, id: "r1", number: 1})
      )

    assert {:error, :seed_closed} = Character.execute(wilted, graduate)
  end

  test "tags are citations: a soul line cites a moment by either party, a pin names the line it evidences, and memory shows the tree's tags through its port",
       ctx do
    id = ctx.resident.id

    :ok =
      AgathosDaimon.write_file(
        id,
        "SOUL.md",
        "# Soul\n\nI check on the garden.",
        %{},
        ctx.witness
      )

    assert {:error, %Ethos.Error{kind: :ethos_not_a_party}} =
             Ethos.cite_soul_line(id, 1, "turn", "t1", Actor.new(:judge, "j", "fake/judge"))

    assert {:error, %Ethos.Error{kind: :ethos_target_invalid}} =
             Ethos.cite_soul_line(id, 9, "turn", "t1", ctx.brain)

    assert {:error, %Ethos.Error{kind: :ethos_target_invalid}} =
             Ethos.cite_soul_line(id, 1, "bookmark", 99, ctx.brain)

    assert :ok = Ethos.cite_soul_line(id, 1, "turn", "t1", ctx.brain)
    assert :ok = Ethos.cite_soul_line(id, 1, "turn", "t1", ctx.witness)
    assert [%{target_kind: "turn", target_id: "t1"}] = Ethos.soul_line_citations(id, 1)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        id,
        %{
          session_key: ctx.key,
          anchor_ref: "t1",
          anchor_at: Clock.now(),
          line: "the tomatoes",
          summary: "s",
          turns_back: 1
        },
        ctx.brain
      )

    # A pin as evidence: the pin carries the line, the line cites the bookmark.
    assert {:error, %Ethos.Error{kind: :ethos_target_invalid}} =
             Ethos.pin_as_evidence(id, n, 9, ctx.witness)

    assert [%{number: ^n, pinned_at: nil, tags: []}] = Kumbukumbu.bookmarks(id)
    assert :ok = Ethos.pin_as_evidence(id, n, 1, ctx.witness)

    assert [%{number: ^n, pinned_by_kind: "witness", pin_evidences: 1, tags: ["soul/1"]}] =
             Kumbukumbu.bookmarks(id)

    assert ["bookmark", "turn"] = id |> Ethos.soul_line_citations(1) |> Enum.map(& &1.target_kind)

    # The tree's tags beside the closed set's, in the index too.
    {:ok, 1} = Ethos.plant_seed(id, "I might be becoming a gardener.", ctx.brain)
    :ok = Ethos.cite_seed(id, 1, "bookmark", n, ctx.brain)

    assert %{to_string(n) => ["seed/1", "soul/1"]} ==
             Ethos.tags_of(id, "bookmark", [to_string(n)])

    assert %{} == Ethos.tags_of(id, "bookmark", ["99"])
    assert Kumbukumbu.index(id).text =~ "[seed/1, soul/1] the tomatoes"

    # Pure: a citation is a set, and the target's kind is the aggregate's to check.
    cite = %Commands.CiteSoulLine{
      actor: ctx.brain,
      at: Clock.now(),
      id: "r1",
      number: 1,
      target_kind: "turn",
      target_id: "t9"
    }

    s = Character.apply(%Character{}, Character.execute(%Character{}, cite))
    assert [] = Character.execute(s, cite)
    assert {:error, :target_invalid} = Character.execute(s, %{cite | target_kind: "mood"})
  end
end
