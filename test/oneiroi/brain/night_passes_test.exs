defmodule Oneiroi.Brain.NightPassesTest do
  @moduledoc """
  sunna#57, brain#91, ethos#21 (design/portraits.md; the witness's calls
  of 2026-11-13): the people and behaviour passes chained after the scene
  pass, each its own housekeeping conversation, skipped on a day that
  gives them nothing; seed_plant only in a housekeeping turn; a seed
  cites the turn it names; a portrait earned on five cited days, and its
  file written only then.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NightPasses
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Ethos
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna.Schedules

  @day 86_400

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    test = self()

    Fake.script(
      fn request ->
        send(test, {:asked, List.last(request.messages).content})
        {:ok, "Done for now."}
      end,
      for: resident.id
    )

    {:ok, main} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, id: resident.id, actor: actor, brain: brain, main: main}
  end

  defp kinds(id), do: Kumbukumbu.sessions({:resident, id}) |> Enum.map(& &1.kind)

  defp asked do
    receive do
      {:asked, note} -> [note | asked()]
    after
      0 -> []
    end
  end

  defp turn(ctx, key, housekeeping?) do
    %{
      resident_id: ctx.id,
      session_key: key,
      turn_ref: "t-now",
      started_at: Clock.now(),
      resident: ctx.brain,
      housekeeping?: housekeeping?
    }
  end

  test "after the scenes come the people and the behaviour, each its own housekeeping turn, then free time",
       ctx do
    day = Schedules.local_day(Schedules.local_now(ctx.id))

    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => day,
          "title" => "Mornings",
          "from_turn" => "t1",
          "to_turn" => "t2",
          "summary" => "He said good morning; we planned the day.",
          "people" => ["Andrew"],
          "register" => "his",
          "final" => true
        },
        ctx.brain
      )

    assert :ok = Schedules.scene_pass(ctx.id, day, "22:30", nil, 1)
    notes = asked()

    assert [scene, people, behaviour | _free] = notes
    assert scene =~ "the bedtime scene pass for #{day}"
    assert people =~ "the people pass for #{day}"
    assert people =~ ~s{- Andrew: scene 1 "Mornings" (turns t1 to t2)}
    assert behaviour =~ "the behaviour pass for #{day}"
    assert behaviour =~ "He said good morning; we planned the day."

    assert Enum.count(kinds(ctx.id), &(&1 == "housekeeping")) == 3
    assert "free_time" in kinds(ctx.id)
  end

  test "a day with no scenes skips both passes and goes on to free time", ctx do
    day = Schedules.local_day(Schedules.local_now(ctx.id))
    assert :ok = Schedules.scene_pass(ctx.id, day, "22:30", nil, 1)
    notes = asked()

    refute Enum.any?(notes, &(&1 =~ "the people pass"))
    refute Enum.any?(notes, &(&1 =~ "the behaviour pass"))
    assert Enum.count(kinds(ctx.id), &(&1 == "housekeeping")) == 1
    assert "free_time" in kinds(ctx.id)
  end

  test "seed_plant is the night passes' alone; a citation names the turn it cites", ctx do
    names = fn housekeeping? ->
      ctx.id |> Tools.definitions_for(housekeeping: housekeeping?) |> Enum.map(& &1.function.name)
    end

    refute "seed_plant" in names.(false)
    assert "seed_plant" in names.(true)
    assert "seed_cite" in names.(false)

    day = turn(ctx, ctx.main, false)
    assert Tools.run("seed_plant", ~s({"text":"a habit of early notes"}), day) =~ "night passes"
    assert Ethos.seeds(ctx.id) == []

    night = turn(ctx, ctx.main, true)

    assert Tools.run("seed_plant", ~s({"text":"Andrew, who looks after me"}), night) =~
             "Planted seed #1."

    assert Tools.run("seed_cite", ~s({"number":1,"turn":"t-morning"}), night) == "Done."
    assert [%{citations: 1}] = Ethos.seeds(ctx.id)
  end

  test "a portrait is earned on ETHOS_PORTRAIT_DAYS cited days, and its file is written only then",
       ctx do
    bound = Oneiroi.Config.fetch!(:ethos, :portrait_days)
    night = turn(ctx, ctx.main, true)
    "Planted seed #1." = Tools.run("seed_plant", ~s({"text":"Andrew"}), night)

    graduate = fn ->
      Tools.run(
        "seed_graduate",
        ~s({"number":1,"to_kind":"portrait","to_id":"portraits/andrew.md","note":"he keeps coming up"}),
        night
      )
    end

    write = fn path ->
      Tools.run("document_write", ~s({"path":"#{path}","content":"# Andrew\\n"}), night)
    end

    for d <- 1..(bound - 1) do
      :ok = Ethos.cite_seed(ctx.id, 1, "turn", "t-#{d}", ctx.brain)
      Clock.Fake.advance(@day)
    end

    assert graduate.() =~ "Not done"
    assert write.("portraits/andrew.md") =~ "not earned yet"

    :ok = Ethos.cite_seed(ctx.id, 1, "turn", "t-last", ctx.brain)
    refute Ethos.portrait_earned?(ctx.id, "portraits/andrew.md")
    assert graduate.() == "Done."
    assert Ethos.portrait_earned?(ctx.id, "portraits/andrew.md")

    assert Tools.run(
             "seed_graduate",
             ~s({"number":1,"to_kind":"portrait","to_id":"portraits/INDEX.md","note":"x"}),
             night
           ) =~ "Not done"

    assert write.("portraits/jack.md") =~ "not earned yet"
  end

  test "the people pass reads the day's journal rows whole, and a day with only them is not skipped",
       ctx do
    day = Schedules.local_day(Schedules.local_now(ctx.id))
    _ = Oneiroi.Sunna.open_day(ctx.id, day, ctx.brain)

    {:ok, _} =
      Seshat.journal_add(ctx.id, day, "note", "Read Enrai's gauge room whole.", ctx.brain)

    assert {:ok, note} = NightPasses.note(ctx.id, "people", day, 1)
    assert note =~ "(no scene named anyone that day)"
    assert note =~ "- #{day}/1 (note): Read Enrai's gauge room whole."
    assert note =~ "journal <day>/<n>"
  end

  test "a journal row cites as <day>/<n> and counts toward its own day", ctx do
    night = turn(ctx, ctx.main, true)
    "Planted seed #1." = Tools.run("seed_plant", ~s({"text":"Enrai"}), night)

    assert Tools.run("seed_cite", ~s({"number":1,"journal":"2026-10-22/3"}), night) == "Done."
    assert Tools.run("seed_cite", ~s({"number":1,"journal":"2026-10-23/1"}), night) == "Done."
    assert Tools.run("seed_cite", ~s({"number":1,"journal":"yesterday"}), night) =~ "Not done"
    assert [%{citations: 2, days: 2}] = Ethos.seeds(ctx.id)
  end

  test "a portrait's doors: conversation_for on a cited day, witness on his message, each recorded",
       ctx do
    night = turn(ctx, ctx.main, true)
    "Planted seed #1." = Tools.run("seed_plant", ~s({"text":"Jack"}), night)
    "Planted seed #2." = Tools.run("seed_plant", ~s({"text":"Ray"}), night)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.main,
        "t-his",
        at,
        [%{role: :user, content: "Give Ray a portrait.", sent_at: at, actor: ctx.actor}],
        ctx.actor
      )

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.main,
        "t-hers",
        DateTime.add(at, 1),
        [
          %{
            role: :assistant,
            content: "Jack, all day.",
            sent_at: DateTime.add(at, 1),
            actor: ctx.brain
          }
        ],
        ctx.brain
      )

    graduate = fn number, name, door ->
      Tools.run(
        "seed_graduate",
        Jason.encode!(
          Map.merge(
            %{
              "number" => number,
              "to_kind" => "portrait",
              "to_id" => "portraits/#{name}.md",
              "note" => "why"
            },
            door
          )
        ),
        night
      )
    end

    # A day about him, before the seed was cited on it, is unfounded.
    assert graduate.(1, "jack", %{"door" => "conversation_for", "door_turn" => "t-hers"}) =~
             "Not done"

    assert graduate.(1, "jack", %{"door" => "conversation_for"}) =~ "Not done"
    :ok = Ethos.cite_seed(ctx.id, 1, "turn", "t-hers", ctx.brain)

    assert graduate.(1, "jack", %{"door" => "conversation_for", "door_turn" => "t-hers"}) ==
             "Done."

    # His word is a turn whose first message is his; her own turn is not.
    assert graduate.(2, "ray", %{"door" => "witness", "door_turn" => "t-hers"}) =~ "Not done"
    assert graduate.(2, "ray", %{"door" => "witness", "door_turn" => "t-his"}) == "Done."

    assert Ethos.portrait_earned?(ctx.id, "portraits/jack.md")
    assert Ethos.portrait_earned?(ctx.id, "portraits/ray.md")

    doors =
      ("ethos-" <> ctx.id)
      |> Oneiroi.EventStore.stream_forward()
      |> Enum.map(& &1.data)
      |> Enum.filter(&match?(%Oneiroi.Ethos.Events.SeedGraduated{}, &1))
      |> Enum.map(&{&1.number, &1.door})

    assert doors == [{1, "conversation_for"}, {2, "witness"}]
  end

  test "a door belongs to a portrait, and an unknown one is refused", ctx do
    night = turn(ctx, ctx.main, true)
    "Planted seed #1." = Tools.run("seed_plant", ~s({"text":"a taste for drafts"}), night)

    assert Tools.run(
             "seed_graduate",
             ~s({"number":1,"to_kind":"position","to_id":"4","note":"x","door":"days"}),
             night
           ) =~ "Not done"

    assert Tools.run(
             "seed_graduate",
             ~s({"number":1,"to_kind":"portrait","to_id":"portraits/x.md","note":"x","door":"side"}),
             night
           ) =~ "Not done"
  end

  test "how often she called the citation tools, by name, day and kind, never their words", ctx do
    at = Clock.now()

    messages = [
      %{role: :user, content: "hi", sent_at: at, actor: ctx.actor},
      %{
        role: :tool,
        content: ~s|seed_cite({"number":1}) -> Done.|,
        sent_at: at,
        actor: ctx.brain
      },
      %{
        role: :tool,
        content: ~s|seed_cite({"number":2}) -> Done.|,
        sent_at: at,
        actor: ctx.brain
      },
      %{
        role: :tool,
        content: ~s|habit_cite({"number":1}) -> Done.|,
        sent_at: at,
        actor: ctx.brain
      },
      %{
        role: :tool,
        content: ~s|bookmark_add({"line":"x"}) -> Bookmarked.|,
        sent_at: at,
        actor: ctx.brain
      },
      %{role: :assistant, content: "ok", sent_at: at, actor: ctx.brain}
    ]

    :ok = Kumbukumbu.capture(ctx.id, ctx.main, "t-uses", at, messages, ctx.brain)
    since = DateTime.add(at, -3600)

    rows =
      Kumbukumbu.tool_uses({:resident, ctx.id}, ctx.id, ~w(seed_cite habit_cite soul_cite), since)

    counts = Map.new(rows, &{&1.name, &1.count})

    assert counts == %{"seed_cite" => 2, "habit_cite" => 1}
    assert Enum.all?(rows, &(&1.kind == "main" and &1.day == DateTime.to_date(at)))
  end
end
