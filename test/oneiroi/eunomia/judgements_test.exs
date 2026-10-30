defmodule Oneiroi.Eunomia.JudgementsTest do
  @moduledoc "Judgement through the exports and the brain: positions and chains, the live check with the judge's advice or a timeout, settlements and the ratio, predictions, the judge's model, the nightly pass within its bounds."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia
  alias Oneiroi.Eunomia.NightWorker
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Nisaba.Provider.Fake

  @since ~U[2026-10-01 00:00:00.000000Z]

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Fake.clear()
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  defp ctx(key), do: %{session_key: key, turn_ref: "t1"}

  # The judge and the resident answer from one fake: the script tells
  # them apart by the model the ledger put on the request.
  defp judge_says(id, text) do
    Fake.script(
      fn
        %{model: "fake/judge"} -> {:ok, text}
        _request -> {:ok, "I hear you."}
      end,
      for: id
    )
  end

  test "positions are the resident's, in chains that cannot fork", ctx do
    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_resident}} =
             Eunomia.take_position(ctx.id, "Tea before coffee.", ctx(ctx.key), ctx.actor)

    assert {:ok, 1} = Eunomia.take_position(ctx.id, "Tea before coffee.", ctx(ctx.key), ctx.brain)

    assert {:ok, 2} =
             Eunomia.take_position(ctx.id, "Mornings are for walking.", ctx(ctx.key), ctx.brain)

    assert {:ok, 3} =
             Eunomia.replace_position(ctx.id, 1, "Coffee, actually.", ctx(ctx.key), ctx.brain)

    assert {:error, %Eunomia.Error{kind: :eunomia_position_replaced}} =
             Eunomia.replace_position(ctx.id, 1, "Neither.", ctx(ctx.key), ctx.brain)

    assert [
             %{number: 1, replaced_by: 3},
             %{number: 2, replaced_by: nil},
             %{number: 3, replaces: 1}
           ] =
             Eunomia.positions(ctx.id)

    assert [2, 3] = ctx.id |> Eunomia.held_positions() |> Enum.map(& &1.number)

    assert {:error, %Eunomia.Error{kind: :eunomia_statement_invalid}} =
             Eunomia.take_position(ctx.id, String.duplicate("x", 1001), ctx(ctx.key), ctx.brain)
  end

  test "a live check records the judge's advice and model, a settlement is the resident's, and the ratio counts earned concessions by week",
       ctx do
    {:ok, 1} = Eunomia.take_position(ctx.id, "It did not rain.", ctx(ctx.key), ctx.brain)
    judge_says(ctx.id, "ADVICE: concede\nThe witness was there and the resident was not.")

    attrs =
      Map.merge(ctx(ctx.key), %{claim: "it rained", stance: "it did not", position_number: 1})

    assert {:ok, %{ref: ref, outcome: "advised", advice: "concede", text: text}} =
             Eunomia.check_dispute(ctx.id, attrs, ctx.brain)

    assert text =~ "was there"
    assert [%{calls: 1, key: "judge"}] = Nisaba.spend(ctx.id, :witness, :purpose, @since)

    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_resident}} =
             Eunomia.check_dispute(ctx.id, attrs, ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_no_such_position}} =
             Eunomia.check_dispute(ctx.id, %{attrs | position_number: 9}, ctx.brain)

    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_resident}} =
             Eunomia.settle_dispute(ctx.id, ref, "conceded", "fair", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_settlement_invalid}} =
             Eunomia.settle_dispute(ctx.id, ref, "won", "x", ctx.brain)

    assert :ok = Eunomia.settle_dispute(ctx.id, ref, "conceded", "fair enough", ctx.brain)

    # A second check, held against the judge's advice: a concession not made.
    judge_says(ctx.id, "ADVICE: hold\nThe stance stands on the stated position.")
    {:ok, %{ref: ref2, advice: "hold"}} = Eunomia.check_dispute(ctx.id, attrs, ctx.brain)
    assert :ok = Eunomia.settle_dispute(ctx.id, ref2, "conceded", "I gave way anyway", ctx.brain)

    disputes = Eunomia.disputes(ctx.id)

    assert %{
             settlement: "conceded",
             advice: "hold",
             judge_model: "fake/judge",
             criteria: criteria
           } =
             Enum.find(disputes, &(&1.ref == ref2))

    # The criteria on the verdict (spec §6.4, P12): the judge's prompt as shipped.
    # Computed here from the file itself, not through the function under test.
    assert criteria ==
             :crypto.hash(:sha256, File.read!(Prompt.path("judge_dispute")))
             |> Base.encode16(case: :lower)

    assert criteria == Prompt.hash("judge_dispute")

    assert %{settlement: "conceded", advice: "concede"} = Enum.find(disputes, &(&1.ref == ref))

    assert %{
             judge_model: "fake/judge",
             weeks: [%{week: "2026-W44", settled: 2, conceded: 2, held: 0, earned: 1, ratio: 1.0}]
           } = Eunomia.judgement(ctx.id)
  end

  test "a judge that does not answer in time is recorded as timed out, unjudged, and the resident answers alone",
       ctx do
    Fake.script(
      fn
        %{model: "fake/judge"} ->
          Process.sleep(600)
          {:ok, "ADVICE: hold"}

        _request ->
          {:ok, "hi"}
      end,
      for: ctx.id
    )

    attrs = Map.merge(ctx(ctx.key), %{claim: "a", stance: "b"})

    assert {:ok, %{outcome: "timed_out", advice: nil}} =
             Eunomia.check_dispute(ctx.id, attrs, ctx.brain)

    assert [%{outcome: "timed_out", advice: nil, judge_model: "fake/judge"}] =
             Eunomia.disputes(ctx.id)
  end

  test "the judge is the witness's to choose and never the resident's own chat model", ctx do
    assert "fake/judge" = Eunomia.judge_model(ctx.id)

    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_witness}} =
             Eunomia.set_judge_model(ctx.id, "fake/other", ctx.brain)

    assert :ok = AgathosDaimon.pin_model(ctx.id, "fake/pinned", "witness", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_judge_is_the_chat_model}} =
             Eunomia.set_judge_model(ctx.id, "fake/pinned", ctx.actor)

    assert :ok = Eunomia.set_judge_model(ctx.id, "fake/other", ctx.actor)
    assert "fake/other" = Eunomia.judge_model(ctx.id)

    assert %{chosen: "fake/other", changes: [%{model: "fake/other", previous: nil}]} =
             Eunomia.judgement(ctx.id)

    # A chat model pinned onto the judge afterwards: the platform's judge stands in.
    assert :ok = AgathosDaimon.pin_model(ctx.id, "fake/other", "witness", ctx.actor)
    assert "fake/judge" = Eunomia.judge_model(ctx.id)
  end

  test "predictions are the resident's to log and the witness's alone to resolve, with a note",
       ctx do
    due = ~U[2026-10-30 09:00:00Z]

    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_resident}} =
             Eunomia.log_prediction(ctx.id, "Rain on Friday.", due, ctx(ctx.key), ctx.actor)

    assert {:ok, 1} =
             Eunomia.log_prediction(ctx.id, "Rain on Friday.", due, ctx(ctx.key), ctx.brain)

    assert {:ok, 2} =
             Eunomia.log_prediction(
               ctx.id,
               "Snow by December.",
               ~U[2026-12-01 00:00:00Z],
               ctx(ctx.key),
               ctx.brain
             )

    assert {:error, %Eunomia.Error{kind: :eunomia_due_invalid}} =
             Eunomia.log_prediction(ctx.id, "Soon.", nil, ctx(ctx.key), ctx.brain)

    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_witness}} =
             Eunomia.resolve_prediction(ctx.id, 1, "right", "it poured", ctx.brain)

    assert :ok = Eunomia.resolve_prediction(ctx.id, 1, "right", "it poured", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_resolution_invalid}} =
             Eunomia.resolve_prediction(ctx.id, 2, "maybe", "x", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_no_such_prediction}} =
             Eunomia.resolve_prediction(ctx.id, 9, "void", "x", ctx.actor)

    assert %{
             open: [%{number: 2}],
             resolved: [%{number: 1, outcome: "right", note: "it poured"}],
             tally: %{"right" => 1}
           } =
             Eunomia.predictions(ctx.id)
  end

  test "the nightly pass reads the day across sessions within its bounds, records what the judge found as settled disputes, runs once, and fails a reply that names a message it was not shown",
       ctx do
    id = ctx.id
    yesterday = ~U[2026-10-25 10:00:00.000000Z]

    messages = [
      %{
        role: :user,
        content: "You said the meeting was Tuesday.",
        sent_at: yesterday,
        actor: ctx.actor
      },
      %{
        role: :assistant,
        content: "I did; it was Wednesday. You are right.",
        sent_at: DateTime.add(yesterday, 60),
        actor: ctx.brain
      },
      %{
        role: :user,
        content: String.duplicate("long ", 2_000),
        sent_at: DateTime.add(yesterday, 120),
        actor: ctx.actor
      }
    ]

    :ok = Kumbukumbu.capture(id, ctx.key, "t-y", yesterday, messages, ctx.brain)

    test = self()

    Fake.script(
      fn
        %{model: "fake/judge", messages: shown} ->
          send(test, {:judge, shown})

          {:ok,
           "DISPUTE [1, 2] conceded | the resident gave way on the day\nSUMMARY: one concession, gracefully made"}

        _request ->
          {:ok, "hi"}
      end,
      for: id
    )

    assert :ok = Eunomia.judge_night(id, "2026-10-25", ctx.actor)
    assert_received {:judge, [%{role: :system, content: listed}, _ask]}
    assert listed =~ "[1] user: You said the meeting"
    assert listed =~ "[3] user: long"
    # The long message is cut at the per-message bound.
    refute listed =~ String.duplicate("long ", 900)

    assert [
             %{
               day: "2026-10-25",
               outcome: "judged",
               messages: 3,
               found: 1,
               judge_model: "fake/judge",
               summary: "one concession" <> _
             }
           ] =
             Eunomia.nights(id)

    assert [
             %{
               source: "night",
               settlement: "conceded",
               settled_by_kind: "judge",
               turn_ref: "t-y",
               advice_text: "the resident gave way on the day"
             }
           ] =
             Eunomia.disputes(id)

    # Once: a second run reads nothing and calls no model.
    assert :already = Eunomia.judge_night(id, "2026-10-25", ctx.actor)
    assert [%{calls: 1, key: "judge"}] = Nisaba.spend(id, :witness, :purpose, @since)

    # A day with nothing said calls no model and is recorded as such.
    assert :ok = Eunomia.judge_night(id, "2026-10-24", ctx.actor)

    assert [
             %{day: "2026-10-25", criteria: criteria},
             %{day: "2026-10-24", messages: 0, judge_model: nil, criteria: nil}
           ] =
             Eunomia.nights(id)

    assert criteria == Prompt.hash("judge_night")

    assert [%{calls: 1}] = Nisaba.spend(id, :witness, :purpose, @since)

    # Out of reach: a future day, or one past the bound.
    assert {:error, %Eunomia.Error{kind: :eunomia_night_out_of_reach}} =
             Eunomia.judge_night(id, "2026-10-27", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_night_out_of_reach}} =
             Eunomia.judge_night(id, "2026-10-01", ctx.actor)

    # A reply naming a message it was not shown fails the night; the night may run again.
    earlier = ~U[2026-10-23 10:00:00.000000Z]

    :ok =
      Kumbukumbu.capture(
        id,
        ctx.key,
        "t-e",
        earlier,
        [%{role: :user, content: "hello", sent_at: earlier, actor: ctx.actor}],
        ctx.brain
      )

    judge_says(id, "DISPUTE [9] held | nonsense\nSUMMARY: x")

    assert {:error, %Eunomia.Error{kind: :eunomia_night_failed}} =
             Eunomia.judge_night(id, "2026-10-23", ctx.actor)

    assert [
             %{day: "2026-10-25"},
             %{day: "2026-10-24"},
             %{day: "2026-10-23", outcome: "failed", reason: reason}
           ] = Eunomia.nights(id)

    assert reason =~ "named message 9"
    judge_says(id, "SUMMARY: nothing to see")
    assert :ok = Eunomia.judge_night(id, "2026-10-23", ctx.actor)
    assert Enum.count(Eunomia.nights(id), &(&1.day == "2026-10-23")) == 2
  end

  test "the nightly job judges yesterday for every active resident and skips a paused one", ctx do
    other_witness = Fixtures.account!()
    other = Fixtures.resident!(other_witness)

    {:ok, _} =
      AgathosDaimon.Router.dispatch(%AgathosDaimon.Commands.PauseResident{
        actor: ctx.actor,
        at: Clock.now(),
        id: other.id,
        reason: "away"
      })

    # Under the sandbox a transaction-local `set_config` outlives its
    # savepoint, so the connection carries whatever scope was set last.
    # It is set to the paused resident's here, so a roster read that
    # skipped its own platform transaction would see one row, the wrong
    # one, and the probe on that line fails rather than printing ok.
    Oneiroi.Scope.resident(other.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = NightWorker.run(%{})
    assert [%{day: "2026-10-25", messages: 0}] = Eunomia.nights(ctx.id)
    assert [] = Eunomia.nights(other.id)
  end

  test "the brain's tools take positions, check and settle a dispute, and log predictions on the turn",
       ctx do
    id = ctx.id
    test = self()

    Fake.script(
      fn
        %{model: "fake/judge"} ->
          {:ok, "ADVICE: hold\nThe position stands."}

        %{messages: messages} ->
          send(test, {:turn, messages})

          if Enum.any?(messages, &(&1.role == :tool)),
            do: {:ok, "I hold my position."},
            else:
              {:calls,
               [
                 %{name: "position_take", arguments: %{statement: "The garden needs no fence."}},
                 %{
                   name: "dispute_check",
                   arguments: %{claim: "fence it", stance: "no fence", position_number: 1}
                 },
                 %{
                   name: "prediction_log",
                   arguments: %{statement: "No deer by spring.", due: "2027-04-01T00:00:00Z"}
                 },
                 %{name: "position_list", arguments: %{}}
               ]}
      end,
      for: id
    )

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "fence the garden", ctx.actor)

    tool_messages = Enum.filter(messages, &(&1.role == :tool))
    assert Enum.any?(tool_messages, &(&1.content =~ "Position #1 taken"))
    assert Enum.any?(tool_messages, &(&1.content =~ "The judge advises: hold"))
    assert Enum.any?(tool_messages, &(&1.content =~ "Prediction #1 logged"))
    assert Enum.any?(tool_messages, &(&1.content =~ "#1 The garden needs no fence"))

    assert [%{number: 1, session_key: key, turn_ref: ref}] = Eunomia.positions(id)
    assert key == ctx.key and is_binary(ref)

    assert [%{ref: dispute_ref, position_number: 1, advice: "hold", settlement: nil}] =
             Eunomia.disputes(id)

    Fake.script(
      fn %{messages: messages} ->
        # The history now carries the first turn's tool messages, so the
        # round is told by the last message rather than by any tool message.
        if List.last(messages).role == :tool,
          do: {:ok, "Settled."},
          else:
            {:calls,
             [
               %{
                 name: "dispute_settle",
                 arguments: %{ref: dispute_ref, outcome: "held", note: "the fence can wait"}
               }
             ]}
      end,
      for: id
    )

    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "fine", ctx.actor)

    assert [
             %{
               settlement: "held",
               settled_note: "the fence can wait",
               settled_by_kind: "resident"
             }
           ] = Eunomia.disputes(id)

    assert %{open: [%{number: 1}]} = Eunomia.predictions(id)
  end
end
