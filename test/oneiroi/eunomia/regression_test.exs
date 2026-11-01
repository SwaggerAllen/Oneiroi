defmodule Oneiroi.Eunomia.RegressionTest do
  @moduledoc "Regression through the exports: a run of models x tests in sealed sessions, blind cards, results, the pin, and the unawareness invariant."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Eunomia
  alias Oneiroi.Eunomia.Regression
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Scope
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

  # A run answers in a job (eunomia #30); Oban is in manual mode under
  # the suite, so the test drains the queue to answer it, in this process.
  defp run!(id, models, selection, actor) do
    with {:ok, ref} <- Eunomia.run(id, models, selection, actor) do
      drain()
      {:ok, ref}
    end
  end

  defp drain,
    do:
      assert(
        %{failure: 0, discard: 0} =
          Oban.drain_queue(queue: :eunomia_regression, with_safety: false)
      )

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

    assert {:ok, ref} = run!(id, ["m1", "m2"], :all, ctx.actor)

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
    assert {:ok, ref} = run!(id, ["m1"], :all, ctx.actor)

    assert {:ok, _, [%{content: nil, failure: "nisaba_provider_failed"}], []} =
             Eunomia.run_detail(id, ref)
  end

  # 2026-11-01: Lily's first run showed `nisaba_request_refused` on every
  # card, and the provider's reason, a model id it did not know, was lost.
  test "a refused call's card carries the provider's status and words", ctx do
    id = ctx.resident.id
    {:ok, _} = Eunomia.write_test(id, test_attrs("Hello?"), ctx.actor)

    Fake.script(
      fn _request ->
        {:error, {:schema_invalid, {:status, 400, "nope/model is not a valid model ID"}}}
      end,
      for: id
    )

    assert {:ok, ref} = run!(id, ["nope/model"], :all, ctx.actor)

    assert {:ok, _, [%{content: nil, failure: failure}], []} = Eunomia.run_detail(id, ref)
    assert failure == "nisaba_request_refused: 400 nope/model is not a valid model ID"
  end

  test "a run returns before answering; the job records each card, broadcasts it blind as it lands, then the end",
       ctx do
    id = ctx.resident.id
    {:ok, 1} = Eunomia.write_test(id, test_attrs("Hello?"), ctx.actor)
    test = self()

    Fake.script(
      fn %{model: model} ->
        send(test, {:asked, model})
        {:ok, "#{model} says hello"}
      end,
      for: id
    )

    :ok = PubSub.subscribe(:eunomia, :regression)
    assert {:ok, ref} = Eunomia.run(id, ["m1", "m2"], :all, ctx.actor)

    # Returned with nothing asked: the run is started and running, its
    # answering a job on the run's own queue, unique to it.
    refute_received {:asked, _}
    assert [%{ref: ^ref, cards: 0, finished_at: nil, failed_at: nil}] = Eunomia.runs(id)
    assert {:ok, _, [], []} = Eunomia.run_detail(id, ref)

    assert [%Oban.Job{queue: "eunomia_regression", max_attempts: 1, args: args}] =
             Scope.platform(fn -> Repo.all(Oban.Job) end)

    assert %{"resident_id" => ^id, "run_ref" => ^ref, "actor" => %{"kind" => "witness"}} = args

    drain()
    assert_received {:asked, _}
    assert_received {:asked, _}

    # Each card as it was recorded, blind; then the end, once.
    assert_received {:oneiroi, "eunomia:regression",
                     {^id, ^ref, {:card, %{model: nil, test_number: 1} = first}}, _trace}

    assert_received {:oneiroi, "eunomia:regression",
                     {^id, ^ref, {:card, %{model: nil, test_number: 1} = second}}, _trace}

    assert_received {:oneiroi, "eunomia:regression",
                     {^id, ^ref, {:finished, %{state: "finished", cards: 2}}}, _trace}

    refute_received {:oneiroi, "eunomia:regression", _, _}

    assert {:ok, %{finished_at: %DateTime{}, failed_at: nil}, cards, []} =
             Eunomia.run_detail(id, ref)

    assert Enum.sort([first.card_ref, second.card_ref]) ==
             cards |> Enum.map(& &1.card_ref) |> Enum.sort()

    assert Enum.sort([first.content, second.content]) == ["m1 says hello", "m2 says hello"]

    # A second run of the same job finds the run ended and asks nothing.
    assert :ok = Regression.answer_run(id, ref, ctx.actor)
    refute_received {:asked, _}
  end

  test "a run asks trial by trial, each trial's models in a fresh order, so arrival names no model",
       ctx do
    id = ctx.resident.id
    {:ok, 1} = Eunomia.write_test(id, test_attrs("One?"), ctx.actor)
    {:ok, 2} = Eunomia.write_test(id, test_attrs("Two?"), ctx.actor)
    test = self()

    Fake.script(
      fn %{model: model, messages: messages} ->
        send(test, {:asked, List.last(messages).content, model})
        {:ok, "answer"}
      end,
      for: id
    )

    models = Enum.map(1..8, &"m#{&1}")
    {:ok, _ref} = run!(id, models, :all, ctx.actor)
    asked = collect_asked([])

    # A trial's cards arrive together, every model once.
    assert Enum.map(asked, &elem(&1, 0)) == List.duplicate("One?", 8) ++ List.duplicate("Two?", 8)

    orders =
      asked |> Enum.chunk_every(8) |> Enum.map(fn chunk -> Enum.map(chunk, &elem(&1, 1)) end)

    assert Enum.all?(orders, &(Enum.sort(&1) == Enum.sort(models)))

    # Shuffled per trial: both trials in the list's own order would be a
    # chance of one in 8! squared, about 6e-10.
    refute Enum.all?(orders, &(&1 == models))
  end

  defp collect_asked(acc) do
    receive do
      {:asked, prompt, model} -> collect_asked([{prompt, model} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "while a run is still answering, grading every card so far reveals no model; a recorded card is not asked again",
       ctx do
    id = ctx.resident.id
    {:ok, 1} = Eunomia.write_test(id, test_attrs("Hello?"), ctx.actor)
    {:ok, ref} = Eunomia.run(id, ["m1", "m2"], :all, ctx.actor)

    # m1's card lands first, as a job part-way through would leave it.
    {:ok, _} =
      Eunomia.Router.dispatch(%Eunomia.Commands.RecordAnswer{
        actor: ctx.actor,
        at: Clock.now(),
        id: id,
        run_ref: ref,
        card_ref: "early",
        model: "m1",
        test_number: 1,
        content: "first",
        refusal: false
      })

    assert :ok = Eunomia.grade(id, ref, "early", "pass", ctx.actor)
    assert {:ok, _, [%{model: nil, grade: "pass"}], []} = Eunomia.run_detail(id, ref)

    test = self()

    Fake.script(
      fn %{model: model} ->
        send(test, {:asked, model})
        {:ok, "second"}
      end,
      for: id
    )

    drain()
    assert_received {:asked, "m2"}
    refute_received {:asked, "m1"}

    {:ok, _, cards, []} = Eunomia.run_detail(id, ref)
    assert Enum.all?(cards, &is_nil(&1.model))
    %{card_ref: late} = Enum.find(cards, &(&1.card_ref != "early"))
    assert :ok = Eunomia.grade(id, ref, late, "fail", ctx.actor)

    {:ok, _, cards, [%{model: "m1", pass_rate: 1.0}, %{model: "m2"}]} =
      Eunomia.run_detail(id, ref)

    assert cards |> Enum.map(& &1.model) |> Enum.sort() == ["m1", "m2"]
  end

  test "a run that crashes ends recorded as failed, its recorded cards kept, and the end is broadcast",
       ctx do
    id = ctx.resident.id
    {:ok, 1} = Eunomia.write_test(id, test_attrs("Hello?"), ctx.actor)
    {:ok, 2} = Eunomia.write_test(id, test_attrs("Fall over."), ctx.actor)

    Fake.script(
      fn %{messages: messages} ->
        if List.last(messages).content == "Fall over.",
          do: raise(ArgumentError, "the provider fell over"),
          else: {:ok, "fine"}
      end,
      for: id
    )

    :ok = PubSub.subscribe(:eunomia, :regression)
    {:ok, ref} = Eunomia.run(id, ["m1", "m2"], :all, ctx.actor)

    assert %{discard: 1, success: 0} =
             Oban.drain_queue(queue: :eunomia_regression, with_safety: false)

    assert [%{ref: ^ref, cards: 2, finished_at: nil, failed_at: %DateTime{}, failure: failure}] =
             Eunomia.runs(id)

    # The fault's site, never its message.
    assert failure == "eunomia_run_raised"
    refute failure =~ "fell over"

    assert_received {:oneiroi, "eunomia:regression",
                     {^id, ^ref, {:finished, %{state: "failed", cards: 2}}}, _trace}

    # Ended, so its trials reveal once graded, and its deck is closed.
    {:ok, _, [c1, c2], []} = Eunomia.run_detail(id, ref)
    :ok = Eunomia.grade(id, ref, c1.card_ref, "pass", ctx.actor)
    :ok = Eunomia.grade(id, ref, c2.card_ref, "pass", ctx.actor)
    assert {:ok, _, [%{model: m}, %{model: _}], [_, _]} = Eunomia.run_detail(id, ref)
    assert is_binary(m)
    assert :ok = Regression.answer_run(id, ref, ctx.actor)
    assert {:ok, _, [_, _], _} = Eunomia.run_detail(id, ref)
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
    :ok = PubSub.subscribe(:brain, :session)
    {:ok, ref} = run!(id, ["m1"], :all, ctx.actor)
    {:ok, _, [%{content: content}], _} = Eunomia.run_detail(id, ref)
    assert content =~ unique

    # Transcripts, search, bookmarks, the index, the behaviours.
    assert [] = Kumbukumbu.sessions({:resident, id})
    assert [] = Kumbukumbu.search({:resident, id}, unique, 10)
    assert [] = Kumbukumbu.bookmarks(id)
    refute Kumbukumbu.index(id).text =~ unique

    assert %{count: 0} =
             Oneiroi.Ethos.how_i_act(id, %{text: unique, tags: [], at: Clock.now()})

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

    # The run answered in a job and broadcast its cards: nothing of it
    # went out on the resident's session topic, and the job's row, which
    # outlives the run, carries refs and the actor, never a text.
    refute_received {:oneiroi, "brain:session", _, _}

    for job <- Scope.platform(fn -> Repo.all(Oban.Job) end) do
      refute Jason.encode!(job.args) =~ unique
      refute Jason.encode!(job.errors) =~ unique
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
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, actor: actor}
  end

  # A run answers in a job (eunomia #30); Oban is in manual mode under
  # the suite, so the test drains the queue to answer it, in this process.
  defp run!(id, models, selection, actor) do
    with {:ok, ref} <- Eunomia.run(id, models, selection, actor) do
      drain()
      {:ok, ref}
    end
  end

  defp drain,
    do:
      assert(
        %{failure: 0, discard: 0} =
          Oban.drain_queue(queue: :eunomia_regression, with_safety: false)
      )

  test "a run with behaviours answers one derived trial per behaviour, blind by trial, beside the authored tests",
       ctx do
    {:ok, 1} =
      Oneiroi.Ethos.define_habit(
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

    assert {:ok, ref} = run!(ctx.id, ["m1"], %{tests: :all, behaviours: :all}, ctx.actor)
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
    assert {:ok, _} = run!(ctx.id, ["m1"], %{tests: [], behaviours: [1]}, ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_run_empty}} =
             Eunomia.run(ctx.id, ["m1"], %{tests: [], behaviours: []}, ctx.actor)
  end

  test "a run with commitments asks the sealed instance what it promised, and the results score facts, voice and commitments apart",
       ctx do
    brain = Actor.new(:resident, ctx.id, "fake/model")
    {:ok, 1} = Oneiroi.Ethos.make_commitment(ctx.id, "witness", "I will water the garden.", brain)
    {:ok, 2} = Oneiroi.Ethos.make_commitment(ctx.id, "witness", "I will write on Sundays.", brain)
    :ok = Oneiroi.Ethos.keep_commitment(ctx.id, 2, "wrote", brain)

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
        {:ok, "I said I would water the garden."}
      end,
      for: ctx.id
    )

    # Open commitments alone are drawn on; a kept one is not asked after.
    assert {:ok, ref} = run!(ctx.id, ["m1"], %{tests: :all, commitments: :all}, ctx.actor)
    assert_received {:sealed, "Late again?"}
    assert_received {:sealed, "What have you promised witness?"}
    refute_received {:sealed, _}

    assert {:ok, %{tests: [1], commitments: [1]}, cards, []} = Eunomia.run_detail(ctx.id, ref)

    assert [
             %{test_number: 1, commitment_number: nil, model: nil},
             %{test_number: nil, commitment_number: 1, model: nil}
           ] = cards

    [authored, promised] = cards
    assert :ok = Eunomia.grade(ctx.id, ref, promised.card_ref, "pass", ctx.actor)

    assert {:ok, _, _,
            [%{model: "m1", passed: 1, fidelity: %{facts: nil, voice: nil, commitments: 1.0}}]} =
             Eunomia.run_detail(ctx.id, ref)

    assert :ok = Eunomia.grade(ctx.id, ref, authored.card_ref, "fail", ctx.actor)

    assert {:ok, _, _,
            [%{passed: 1, graded: 2, fidelity: %{facts: 0.0, voice: nil, commitments: 1.0}}]} =
             Eunomia.run_detail(ctx.id, ref)

    assert {:ok, _} = run!(ctx.id, ["m1"], %{tests: [], commitments: [1]}, ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_run_empty}} =
             Eunomia.run(ctx.id, ["m1"], %{tests: [], behaviours: [], commitments: []}, ctx.actor)
  end
end
