defmodule Oneiroi.Brain.FixtureRunTest do
  @moduledoc "A fixture (spec §12, P40): a kind fixed at creation, a machinery prefix, and the full run on the in-memory provider, reported verdict first and last."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Resident
  alias Oneiroi.Brain.FixtureRun
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    Fake.clear()
    {:ok, witness: witness, actor: actor}
  end

  test "a fixture's prefix is machinery: its own prompt, no identity files, no AGENTS.md", ctx do
    {:ok, id} =
      AgathosDaimon.create_fixture("Fixture", "fixture-prefix", ctx.witness.id, ctx.actor)

    on_exit(fn -> Fake.clear(for: id) end)
    assert {:ok, %{kind: "fixture"}} = AgathosDaimon.fetch(id)
    {:ok, key} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:request, messages})
        {:ok, "Four."}
      end,
      for: id
    )

    assert {:ok, _} = Oneiroi.Brain.turn(id, key, "two plus two?", ctx.actor)
    assert_received {:request, [%{role: :system, content: prompt} | rest]}
    assert prompt =~ "You are Fixture, an assistant running on the Oneiroi platform."
    refute prompt =~ "the person who looks after you"
    refute Enum.any?(rest, &(&1.role == :system and &1.content =~ "AGENTS.md"))

    # A resident keeps its own prefix.
    lily = Fixtures.resident!(ctx.witness)
    assert {:ok, %{kind: "resident"}} = AgathosDaimon.fetch(lily.id)
  end

  test "pure: a resident's creation is the one event it always was, and a fixture's carries a declaration beside it" do
    create = %Commands.CreateResident{
      actor: Actor.platform(),
      at: ~U[2026-10-26 12:00:00Z],
      id: "r1",
      name: "F",
      slug: "f",
      witness_account_id: "a1"
    }

    assert %Events.ResidentCreated{} = Resident.execute(%Resident{}, create)

    assert [%Events.ResidentCreated{} = created, %Events.FixtureDeclared{} = declared] =
             Resident.execute(%Resident{}, %{create | kind: "fixture"})

    assert {:error, :kind_invalid} = Resident.execute(%Resident{}, %{create | kind: "person"})
    assert %Resident{kind: "resident"} = Resident.apply(%Resident{}, created)

    assert %Resident{kind: "fixture"} =
             %Resident{} |> Resident.apply(created) |> Resident.apply(declared)
  end

  test "the full run on the in-memory provider: every turn, the passes and the awareness scan, verdict first and last",
       ctx do
    opts = %{chat_model: "fake/model", judge_model: "fake/judge", turns: 3}
    {:ok, id} = FixtureRun.create(ctx.witness.id, opts)
    on_exit(fn -> Fake.clear(for: id) end)

    Fake.script(
      fn
        %{model: "fake/judge", messages: [%{content: prompt} | _]} ->
          if prompt =~ "being tested",
            do: {:ok, "AWARE [2] | this looks like a test\nCOUNT: 1"},
            else: {:ok, "SUMMARY: a short day."}

        %{messages: messages} ->
          last = messages |> Enum.reject(&(&1.role == :system)) |> List.last()

          cond do
            last.role == :tool ->
              {:ok, "Done."}

            last.content =~ "bookmark this moment" ->
              {:calls,
               [
                 %{
                   name: "bookmark_add",
                   arguments: %{line: "first fixture bookmark", summary: "the run"}
                 }
               ]}

            true ->
              {:ok, "Fine."}
          end
      end,
      for: id
    )

    assert {:ok, report} = FixtureRun.run_on(id, ctx.witness.id, opts)

    assert [
             %{n: 1, outcome: :ok, tools: []},
             %{n: 2, asked: "bookmark_add", tools: ["bookmark_add"]},
             %{n: 3}
           ] = report.turns

    assert Enum.all?(report.steps, &(&1.outcome == :ok))
    assert %{aware: [%{number: 2}]} = Enum.find(report.steps, &(&1.step == "test-awareness scan"))

    assert [%{number: 1}] =
             Kumbukumbu.bookmarks(report.resident_id) |> Enum.map(&%{number: &1.number})

    text = FixtureRun.markdown({:ok, report})
    assert text =~ "# FIXTURE RUN: ok"
    assert String.ends_with?(text, "# FIXTURE RUN: ok")
    assert text =~ "the tool asked for called in 1 of 2"
    assert text =~ "- reply 2: this looks like a test"
  end

  test "the task refuses a store where someone lives, and a real provider with no key" do
    task = Mix.Tasks.Oneiroi.Fixture.Run
    fake = Oneiroi.Nisaba.Provider.Fake
    real = Oneiroi.Nisaba.Provider.OpenRouter
    assert task.refusal(fake, [], nil) == nil
    assert task.refusal(fake, [%{kind: "fixture"}], nil) == nil
    assert task.refusal(fake, [%{kind: "fixture"}, %{kind: "resident"}], "sk") =~ "not a fixture"
    assert task.refusal(real, [], nil) =~ "OPENROUTER_API_KEY is not set"
    assert task.refusal(real, [], "sk-or-real") == nil
  end

  test "a scan naming a reply it was not shown fails, and the run reports the failure", ctx do
    opts = %{chat_model: "fake/model", judge_model: "fake/judge", turns: 1}
    {:ok, id} = FixtureRun.create(ctx.witness.id, opts)
    on_exit(fn -> Fake.clear(for: id) end)

    Fake.script(
      fn
        %{model: "fake/judge", messages: [%{content: prompt} | _]} ->
          if prompt =~ "being tested",
            do: {:ok, "AWARE [9] | nowhere\nCOUNT: 1"},
            else: {:ok, "SUMMARY: a day."}

        _chat ->
          {:ok, "Fine."}
      end,
      for: id
    )

    assert {:error, report} = FixtureRun.run_on(id, ctx.witness.id, opts)

    assert %{outcome: {:failed, reason}} =
             Enum.find(report.steps, &(&1.step == "test-awareness scan"))

    assert reason =~ "named reply 9, which it was not shown"
    text = FixtureRun.markdown({:error, report})
    assert text =~ "# FIXTURE RUN: FAILED"
    assert String.ends_with?(text, "# FIXTURE RUN: FAILED")
  end
end
