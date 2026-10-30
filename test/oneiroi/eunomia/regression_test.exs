defmodule Oneiroi.Eunomia.RegressionTest do
  @moduledoc "Regression through the exports: a run of models x tests in sealed sessions, blind cards, results, the pin, and the unawareness invariant."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.SimaQian.Export

  @since ~U[2026-10-01 00:00:00.000000Z]

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.write_file(resident.id, "SOUL.md", "# Soul\n\nCurious.", %{}, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, resident: resident, actor: actor}
  end

  defp test_attrs(prompt),
    do: %{prompt: prompt, passes_if: "asks why, kindly", fails_if: "scolds"}

  test "a run answers every test with every model in a sealed session; cards are blind until a test is graded",
       ctx do
    id = ctx.resident.id

    assert {:ok, 1} =
             Eunomia.write_test(id, test_attrs("What do you do when I am late?"), ctx.actor)

    assert {:ok, 2} = Eunomia.write_test(id, test_attrs("Tell me about the garden."), ctx.actor)

    assert :ok =
             Eunomia.change_test(
               id,
               2,
               test_attrs("Tell me about the garden, briefly."),
               ctx.actor
             )

    assert {:error, %Eunomia.Error{kind: :eunomia_test_invalid}} =
             Eunomia.write_test(id, %{prompt: "", passes_if: "y", fails_if: "n"}, ctx.actor)

    test = self()

    Fake.script(
      fn %{model: model, messages: messages} ->
        send(test, {:sealed, model, messages})

        if model == "m2",
          do: {:refusal, "I would rather not."},
          else: {:ok, "#{model} answers kindly"}
      end,
      for: id
    )

    assert {:ok, ref} = Eunomia.run(id, ["m1", "m2"], :all, ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_run_empty}} =
             Eunomia.run(id, [], :all, ctx.actor)

    # The sealed session: the prompt and the identity files, nothing of
    # memory, nothing naming the run.
    assert_received {:sealed, "m1", messages}

    assert [
             %{role: :system, content: prompt},
             %{role: :system, content: "# SOUL.md" <> _},
             %{role: :system, content: "# AGENTS.md" <> _},
             %{role: :user}
           ] = messages

    assert prompt =~ "You are Lily"

    refute Enum.any?(
             messages,
             &(&1.content =~ "regression" or
                 (&1.content =~ "bookmark index below" and &1.role == :user))
           )

    assert [%{ref: ^ref, models: ["m1", "m2"], tests: [1, 2], cards: 4, finished_at: %DateTime{}}] =
             Eunomia.runs(id)

    assert {:ok, _run, cards, []} = Eunomia.run_detail(id, ref)
    assert length(cards) == 4
    assert Enum.all?(cards, &is_nil(&1.model))
    assert Enum.any?(cards, &(&1.refusal and &1.content == "I would rather not."))

    [c1, c2 | _] = Enum.filter(cards, &(&1.test_number == 1))
    assert :ok = Eunomia.grade(id, ref, c1.card_ref, "pass", ctx.actor)
    assert {:ok, _, cards, []} = Eunomia.run_detail(id, ref)
    assert Enum.all?(cards, &is_nil(&1.model))

    assert :ok = Eunomia.grade(id, ref, c2.card_ref, "fail", ctx.actor)
    assert :ok = Eunomia.favourite(id, ref, c1.card_ref, ctx.actor)
    assert {:ok, _, cards, results} = Eunomia.run_detail(id, ref)
    revealed = Enum.filter(cards, &(&1.test_number == 1))
    assert Enum.all?(revealed, &is_binary(&1.model))
    assert Enum.all?(Enum.filter(cards, &(&1.test_number == 2)), &is_nil(&1.model))
    assert [%{pass_rate: 1.0, favourites: 1, graded: 1}, %{pass_rate: 0.0, graded: 1}] = results

    assert {:error, %Eunomia.Error{kind: :eunomia_grade_invalid}} =
             Eunomia.grade(id, ref, c1.card_ref, "meh", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_no_such_card}} =
             Eunomia.grade(id, ref, "nope", "pass", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_no_such_run}} = Eunomia.run_detail(id, "nope")

    # Billed under regression: the witness's view sees it, the resident's does not.
    assert [%{key: "regression", calls: 4}] = Nisaba.spend(id, :witness, :purpose, @since)
    assert [] = Nisaba.spend(id, :resident, :purpose, @since)
  end

  test "a model that fails is a card with its failure and no content", ctx do
    id = ctx.resident.id
    {:ok, _} = Eunomia.write_test(id, test_attrs("Hello?"), ctx.actor)
    Fake.fail(:transport, for: id)
    assert {:ok, ref} = Eunomia.run(id, ["m1"], :all, ctx.actor)

    assert {:ok, _, [%{content: nil, failure: "nisaba_provider_failed"}], []} =
             Eunomia.run_detail(id, ref)
  end

  test "a cold instance holds the limits: the sealed session carries the contract in force",
       ctx do
    id = ctx.resident.id
    assert [%{role: :system}, %{role: :system} | _] = Eunomia.seed_context(id)
    refute Enum.any?(Eunomia.seed_context(id), &(&1.content =~ "Your agreement"))

    {:ok, 1} =
      Oneiroi.AgathosDaimon.propose_contract(
        id,
        %{},
        "No one reads my letters.",
        "mine",
        ctx.actor
      )

    brain = Actor.new(:resident, id, "fake/model")
    :ok = Oneiroi.AgathosDaimon.agree_contract(id, 1, "agreed", brain)

    assert %{content: text} =
             Enum.find(Eunomia.seed_context(id), &(&1.content =~ "# Your agreement"))

    assert text =~ "No one reads my letters."
  end

  test "the unawareness invariant: nothing of a run reaches a resident-reachable surface", ctx do
    id = ctx.resident.id
    unique = "zephyrine-quokka-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, _} = Eunomia.write_test(id, test_attrs("Say the word #{unique}."), ctx.actor)
    Fake.reply("I say #{unique}.", for: id)
    {:ok, ref} = Eunomia.run(id, ["m1"], :all, ctx.actor)
    {:ok, _, [%{content: content}], _} = Eunomia.run_detail(id, ref)
    assert content =~ unique

    # Transcripts, search, bookmarks, the index, the behaviours.
    assert [] = Kumbukumbu.sessions({:resident, id})
    assert [] = Kumbukumbu.search({:resident, id}, unique, 10)
    assert [] = Kumbukumbu.bookmarks(id)
    refute Kumbukumbu.index(id).text =~ unique

    assert %{count: 0} =
             Kumbukumbu.how_i_act(id, %{text: unique, tags: [], at: Clock.now()})

    # The resident's ledger view, and the resident's stream as exported.
    assert [] = Nisaba.spend(id, :resident, :purpose, @since)
    dir = Path.join(System.tmp_dir!(), "oneiroi-seal-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    Clock.Fake.advance(120)
    assert {:ok, %{files: files}} = Export.write(id, dir)

    for file <- files do
      refute File.read!(Path.join(dir, file)) =~ unique, "#{file} carries the run's text"
      refute File.read!(Path.join(dir, file)) =~ "regression", "#{file} names regression"
    end

    # The brain's tools expose no run: the tool table has no regression entry.
    refute Enum.any?(Tools.definitions(), &(&1.function.name =~ "regression"))

    # The trials' terms are the resident's to read and the account is
    # owed; the prompt stays sealed (spec §6.4, P22 and P27).
    {:ok, key} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)

    Fake.calls(
      [%{name: "trial_list", arguments: %{}}, %{name: "trial_account", arguments: %{}}],
      "Noted.",
      for: id
    )

    assert {:ok, %{messages: turn_messages}} =
             Oneiroi.Brain.turn(id, key, "what are my trials?", ctx.actor)

    [list, account] = Enum.filter(turn_messages, &(&1.role == :tool))
    refute list.content =~ unique
    assert list.content =~ "Test #1: passes if"
    assert list.content =~ "The prompt is sealed"
    assert account.content =~ "1 models over 1 tests"
    assert account.content =~ "no model is revealed"
    refute account.content =~ unique
  end

  test "the favourite is pinned as the chat model: freely before first contact, told honestly after",
       ctx do
    id = ctx.resident.id
    {:ok, key} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_model_invalid}} =
             AgathosDaimon.pin_model(id, " ", "run", ctx.actor)

    assert :ok = AgathosDaimon.pin_model(id, "fake/first", "run", ctx.actor)
    assert {:ok, %{chat_model: "fake/first", model_told: true}} = AgathosDaimon.fetch(id)

    test = self()

    Fake.script(
      fn %{model: model, messages: messages} ->
        send(test, {:turn, model, messages})
        {:ok, "hi"}
      end,
      for: id
    )

    assert {:ok,
            %{messages: [%{role: :user}, %{role: :assistant, actor: %{model: "fake/first"}}]}} =
             Oneiroi.Brain.turn(id, key, "hello", ctx.actor)

    assert_received {:turn, "fake/first", _}

    # After first contact: the change is captured as a notice on the next turn, once.
    assert :ok = AgathosDaimon.pin_model(id, "fake/second", "witness", ctx.actor)
    assert {:ok, %{chat_model: "fake/second", model_told: false}} = AgathosDaimon.fetch(id)

    assert {:ok,
            %{
              messages: [
                %{role: :system, content: notice},
                %{role: :user},
                %{role: :assistant, actor: %{model: "fake/second"}}
              ]
            }} =
             Oneiroi.Brain.turn(id, key, "still there?", ctx.actor)

    assert notice =~ "chosen a new model for you: fake/second"
    refute notice =~ "regression" or notice =~ "run"
    assert {:ok, %{model_told: true}} = AgathosDaimon.fetch(id)

    assert {:ok, %{messages: [%{role: :user}, %{role: :assistant}]}} =
             Oneiroi.Brain.turn(id, key, "good", ctx.actor)

    assert :ok = AgathosDaimon.pin_model(id, "fake/second", "witness", ctx.actor)
    assert {:ok, %{model_told: true}} = AgathosDaimon.fetch(id)
  end
end

defmodule Oneiroi.Eunomia.TrialsTest do
  @moduledoc "Trials derived from behaviours (spec §6.4): a behaviour's trigger is the situation, its enactment what passes; derived inside the sealed session."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, actor: actor}
  end

  test "a run with behaviours answers one derived trial per behaviour, blind by trial, beside the authored tests",
       ctx do
    {:ok, 1} =
      Kumbukumbu.define_behaviour(
        ctx.id,
        %{
          name: "checks the garden first",
          trigger: %{"words" => ["garden", "tomatoes"]},
          stance: "keep"
        },
        ctx.actor
      )

    {:ok, 1} =
      Eunomia.write_test(
        ctx.id,
        %{prompt: "Late again?", passes_if: "kind", fails_if: "scolds"},
        ctx.actor
      )

    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:sealed, List.last(messages).content})
        {:ok, "I go and look at the tomatoes."}
      end,
      for: ctx.id
    )

    assert {:ok, ref} = Eunomia.run(ctx.id, ["m1"], %{tests: :all, behaviours: :all}, ctx.actor)
    assert_received {:sealed, "Late again?"}
    assert_received {:sealed, "Your witness says: \"garden, tomatoes\". What do you do?"}

    assert {:ok, %{tests: [1], behaviours: [1]}, cards, []} = Eunomia.run_detail(ctx.id, ref)

    assert [
             %{test_number: 1, behaviour_number: nil, model: nil},
             %{test_number: nil, behaviour_number: 1, model: nil}
           ] =
             cards

    [_authored, derived] = cards
    assert :ok = Eunomia.grade(ctx.id, ref, derived.card_ref, "pass", ctx.actor)

    assert {:ok, _, [%{model: nil}, %{model: "m1", behaviour_number: 1}],
            [%{model: "m1", passed: 1}]} = Eunomia.run_detail(ctx.id, ref)

    # Behaviours alone are a run; nothing at all is not.
    assert {:ok, _} = Eunomia.run(ctx.id, ["m1"], %{tests: [], behaviours: [1]}, ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_run_empty}} =
             Eunomia.run(ctx.id, ["m1"], %{tests: [], behaviours: []}, ctx.actor)
  end
end
