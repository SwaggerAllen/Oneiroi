defmodule Oneiroi.HuginnMuninn.ChecksTest do
  @moduledoc "Figures and audits through the exports and the brain: a counter folded with its actors, a countdown from a date, the built-in checklist over rows, the steward's rules, the light, the nightly job."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.HuginnMuninn.NightlyWorker
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Sunna

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    actor = Actor.new(:steward, steward.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, steward.id, actor)
    Model.clear()
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok, steward: steward, id: resident.id, actor: actor, brain: brain, key: key}
  end

  test "a counter is the steward's to define, either party's to increment with their name, and a countdown is a date read fresh; the brain is shown both",
       ctx do
    id = ctx.id

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_not_the_steward}} =
             HuginnMuninn.define_counter(id, "tea", "Cups of tea", ctx.brain)

    assert :ok = HuginnMuninn.define_counter(id, "tea", "Cups of tea", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_key_invalid}} =
             HuginnMuninn.define_counter(id, "Cups", "x", ctx.actor)

    assert :ok = HuginnMuninn.increment(id, "tea", 1, "with breakfast", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_increment_invalid}} =
             HuginnMuninn.increment(id, "tea", 0, "x", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_no_such_figure}} =
             HuginnMuninn.increment(id, "coffee", 1, "x", ctx.actor)

    {:ok, 1} =
      Sunna.set_date(
        id,
        nil,
        %{title: "the interview", on: ~U[2026-11-05 14:00:00Z], kind: "deadline"},
        ctx.actor
      )

    assert [
             %{key: "tea", kind: "counter", value: 1, increments: 1, last_by: "steward"},
             %{key: "date/1", kind: "countdown", value: 10, label: "the interview"}
           ] = HuginnMuninn.figures(id)

    assert %{kind: "countdown", value: 10} = HuginnMuninn.figure(id, "date/1")
    Clock.Fake.advance(24 * 3600)
    assert %{value: 9} = HuginnMuninn.figure(id, "date/1")

    # The brain increments from its tool and is shown the section.
    test = self()

    Model.script(
      fn %{messages: messages} ->
        send(test, {:shown, messages})

        if List.last(messages).role == :tool,
          do: {:ok, "Counted."},
          else:
            {:calls,
             [
               %{name: "figure_increment", arguments: %{key: "tea", note: "one more"}},
               %{name: "figure_list", arguments: %{}}
             ]}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref, messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "tea?", ctx.actor)

    assert_received {:shown, shown}
    assert Enum.any?(shown, &(&1.role == :system and &1.content =~ "Cups of tea: 1 (figure/tea)"))

    assert Enum.any?(
             Kumbukumbu.injections({:account, ctx.steward.id}, ref),
             &(&1.label == "figures")
           )

    assert Enum.any?(messages, &(&1.role == :tool and &1.content =~ "figure/tea Cups of tea: 2"))

    assert %{value: 2, increments: 2, last_by: "resident"} = HuginnMuninn.figure(id, "tea")

    assert [%{by: 1, actor_kind: "resident", note: "one more"}, %{by: 1, actor_kind: "steward"}] =
             HuginnMuninn.increments(id, "tea", 10)

    assert :ok = HuginnMuninn.retire_counter(id, "tea", ctx.actor)
    assert [%{key: "date/1"}] = HuginnMuninn.figures(id)
    assert "" == HuginnMuninn.figures_text(id)
  end

  test "the built-in audits read rows, the steward's rules read figures, and the light is the failing results of the audits that count",
       ctx do
    id = ctx.id

    assert {:ok, %{state: "ok", findings: [], results: results}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert Enum.map(results, & &1.key) |> Enum.sort() ==
             ~w(attestation capture_failures missed_checkins overdue_predictions sync_failures)

    assert Enum.all?(results, &(&1.tone == "ok"))

    # A capture failure fails a counting audit; resolving it clears the light.
    :ok = Kumbukumbu.fail_capture(id, ctx.key, "t-f", "boom", ctx.brain)

    assert {:ok, %{state: "fail", findings: [%{key: "capture_failures", tone: "fail", value: 1}]}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert %{state: "fail"} = HuginnMuninn.light(id)

    :ok =
      Kumbukumbu.resolve_failure(id, ctx.key, "t-f", "marked_lost", "gone for good", ctx.actor)

    # A root mismatch on the resident row fails the attestation audit until the next backup.
    {:ok, _} =
      AgathosDaimon.Router.dispatch(%AgathosDaimon.Commands.RecordMismatch{
        actor: ctx.actor,
        at: Clock.now(),
        id: id,
        expected_root: "aaa",
        actual_root: "bbb",
        commit: "deadbeef"
      })

    assert {:ok, %{state: "fail", findings: [%{key: "attestation"}]}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    # Overdue predictions and missed check-ins warn and do not count.
    {:ok, 1} =
      Eunomia.log_prediction(
        id,
        "Rain yesterday.",
        ~U[2026-10-25 00:00:00Z],
        %{session_key: ctx.key, turn_ref: "t1"},
        ctx.brain
      )

    for time <- ~w(12:05 12:06 12:07) do
      {:ok, _} = Sunna.set_checkin(id, nil, "c-" <> time, time, ctx.actor)
    end

    Clock.Fake.advance(30 * 60)
    :ok = Sunna.tick(id)

    assert {:ok, %{state: "fail", findings: findings, results: results}} =
             HuginnMuninn.run_audits(id, ctx.actor)

    assert Enum.map(findings, & &1.key) == ["attestation"]
    assert %{tone: "warn", value: 1} = Enum.find(results, &(&1.key == "overdue_predictions"))
    assert %{tone: "warn", value: 3} = Enum.find(results, &(&1.key == "missed_checkins"))

    # The steward's rule over a figure: counts, so it reaches the light.
    :ok = HuginnMuninn.define_counter(id, "tea", "Cups of tea", ctx.actor)
    :ok = HuginnMuninn.increment(id, "tea", 2, "two", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_not_the_steward}} =
             HuginnMuninn.define_audit(
               id,
               %{key: "tea-enough", label: "Enough tea", figure: "tea", op: ">=", value: 3},
               ctx.brain
             )

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_rule_invalid}} =
             HuginnMuninn.define_audit(
               id,
               %{key: "tea-enough", label: "Enough tea", figure: "tea", op: "~", value: 3},
               ctx.actor
             )

    assert :ok =
             HuginnMuninn.define_audit(
               id,
               %{
                 key: "tea-enough",
                 label: "Enough tea",
                 figure: "tea",
                 op: ">=",
                 value: 3,
                 tone: "warn"
               },
               ctx.actor
             )

    assert :ok =
             HuginnMuninn.define_audit(
               id,
               %{
                 key: "tea-quiet",
                 label: "Not too much",
                 figure: "tea",
                 op: "<=",
                 value: 5,
                 tone: "fail",
                 counts: false
               },
               ctx.actor
             )

    assert :ok =
             HuginnMuninn.define_audit(
               id,
               %{
                 key: "ghost",
                 label: "A missing figure",
                 figure: "nope",
                 op: "==",
                 value: 0,
                 tone: "fail"
               },
               ctx.actor
             )

    assert {:ok, %{findings: findings, results: results}} = HuginnMuninn.run_audits(id, ctx.actor)
    assert Enum.map(findings, & &1.key) |> Enum.sort() == ["attestation", "ghost", "tea-enough"]

    assert %{tone: "warn", value: 2, finding: "Enough tea: 2 is not >= 3"} =
             Enum.find(results, &(&1.key == "tea-enough"))

    assert %{tone: "ok", value: 2} = Enum.find(results, &(&1.key == "tea-quiet"))

    assert %{tone: "fail", finding: "figure nope does not exist"} =
             Enum.find(results, &(&1.key == "ghost"))

    :ok = HuginnMuninn.increment(id, "tea", 1, "three", ctx.actor)
    assert :ok = HuginnMuninn.retire_audit(id, "ghost", ctx.actor)

    assert {:error, %HuginnMuninn.Error{kind: :huginn_muninn_no_such_audit}} =
             HuginnMuninn.retire_audit(id, "ghost", ctx.actor)

    assert {:ok, %{findings: [%{key: "attestation"}]}} = HuginnMuninn.run_audits(id, ctx.actor)

    audits = HuginnMuninn.audits(id)
    assert Enum.count(audits, & &1.builtin) == 5

    assert %{builtin: false, counts: true, last: %{tone: "ok", value: 3}} =
             Enum.find(audits, &(&1.key == "tea-enough"))

    refute Enum.any?(audits, &(&1.key == "ghost"))
  end

  test "the nightly job runs every active resident's audits", ctx do
    other = Fixtures.resident!(Fixtures.account!())
    Oneiroi.Scope.resident(other.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = NightlyWorker.run(%{})
    assert %{results: [_, _, _, _, _]} = HuginnMuninn.light(ctx.id)
    assert %{results: [_, _, _, _, _]} = HuginnMuninn.light(other.id)
  end
end
