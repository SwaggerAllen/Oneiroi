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

  test "a portrait is earned on five cited days, and its file is written only then", ctx do
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

    for d <- 1..4 do
      :ok = Ethos.cite_seed(ctx.id, 1, "turn", "t-#{d}", ctx.brain)
      Clock.Fake.advance(@day)
    end

    assert graduate.() =~ "Not done"
    assert write.("portraits/andrew.md") =~ "not earned yet"

    :ok = Ethos.cite_seed(ctx.id, 1, "turn", "t-5", ctx.brain)
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
