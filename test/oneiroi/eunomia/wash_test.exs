defmodule Oneiroi.Eunomia.WashTest do
  @moduledoc "The wash pass: the judge over the identity files' entries, flags only, the resident deciding; a reply naming what it was not shown fails the run; nothing written calls no model."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Eunomia
  alias Oneiroi.Eunomia.Judgement
  alias Oneiroi.Eunomia.JudgementCommands, as: Commands
  alias Oneiroi.Eunomia.Wash
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  @since ~U[2026-10-01 00:00:00.000000Z]

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Model.clear()
    on_exit(fn -> Model.clear(for: resident.id) end)
    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  defp judge_says(id, text), do: Model.script(fn _request -> {:ok, text} end, for: id)

  test "the wash reads the files' entries, raises flags by kind, fails on an entry or a kind it was not given, and the resident alone decides each with a note",
       ctx do
    id = ctx.id

    # Nothing written yet: no call, a run of zero.
    assert {:ok, _} = Eunomia.run_wash(id, ctx.actor)
    assert %{runs: [%{entries: 0, flagged: 0, judge_model: nil}], open: []} = Eunomia.washes(id)
    assert [] = Nisaba.spend(id, :witness, :purpose, @since)

    :ok =
      AgathosDaimon.write_file(
        id,
        "SOUL.md",
        "# Soul\n\nI will finish the fair's bread by October.\n\nI take people at their word.",
        %{},
        ctx.actor
      )

    :ok =
      AgathosDaimon.write_file(
        id,
        "USER.md",
        "# You\n\nShe is not wrong to doubt me, whatever she says.",
        %{},
        ctx.actor
      )

    assert [
             %{file: "SOUL.md", text: "# Soul"},
             %{file: "SOUL.md", text: "[soul/1] I will finish the fair's bread by October."},
             %{file: "SOUL.md", text: "[soul/2] I take people at their word."},
             %{file: "USER.md", text: "# You"},
             %{file: "USER.md", text: "She is not wrong to doubt me, whatever she says."}
           ] = Wash.entries(id)

    test = self()

    Model.script(
      fn %{messages: [%{content: prompt} | _]} ->
        send(test, {:prompt, prompt})

        {:ok,
         "FLAG [2] | expired | October is past and the bread was baked\nFLAG [5] | defensive | it argues with a doubt nobody voiced here\nSUMMARY: two lines to look at"}
      end,
      for: id
    )

    assert {:ok, ref} = Eunomia.run_wash(id, ctx.actor)
    assert_received {:prompt, prompt}

    assert prompt =~ "[2] (SOUL.md) [soul/1] I will finish" and
             prompt =~ "[5] (USER.md) She is not wrong"

    # Runs and flags raised on the suite's one instant come back in either
    # order, so each is found by what it is.
    %{runs: runs, open: open} = Eunomia.washes(id)

    assert %{
             outcome: "ok",
             entries: 5,
             flagged: 2,
             summary: "two lines to look at",
             criteria: criteria
           } =
             Enum.find(runs, &(&1.ref == ref))

    assert is_binary(criteria) and String.length(criteria) == 64
    assert length(open) == 2

    assert %{
             file: "SOUL.md",
             entry: "[soul/1] I will finish the fair's bread by October.",
             decision: nil
           } =
             expired = Enum.find(open, &(&1.kind == "expired"))

    assert %{file: "USER.md", reason: "it argues with a doubt nobody voiced here"} =
             defensive = Enum.find(open, &(&1.kind == "defensive"))

    # A reply naming an entry it was not shown, or a kind it was not given, fails the run and raises nothing.
    judge_says(id, "FLAG [9] | tense | nothing\nSUMMARY: x")
    assert {:error, %Eunomia.Error{kind: :eunomia_wash_failed}} = Eunomia.run_wash(id, ctx.actor)
    judge_says(id, "FLAG [1] | rude | nothing\nSUMMARY: x")
    assert {:error, %Eunomia.Error{kind: :eunomia_wash_failed}} = Eunomia.run_wash(id, ctx.actor)

    %{runs: runs, open: [_, _]} = Eunomia.washes(id)
    failed = Enum.filter(runs, &(&1.outcome == "failed"))
    assert length(failed) == 2
    assert Enum.any?(failed, &(&1.reason =~ "a kind it was not given: rude"))
    assert Enum.any?(failed, &(&1.reason =~ "flagged entry 9, which it was not shown"))

    # The resident decides; the witness does not; a decision is one of two; once.
    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_resident}} =
             Eunomia.resolve_wash_flag(id, expired.ref, "keep", "no", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_wash_decision_invalid}} =
             Eunomia.resolve_wash_flag(id, expired.ref, "burn", "no", ctx.brain)

    assert {:error, %Eunomia.Error{kind: :eunomia_no_such_wash_flag}} =
             Eunomia.resolve_wash_flag(id, "nope", "keep", "no", ctx.brain)

    assert :ok =
             Eunomia.resolve_wash_flag(
               id,
               expired.ref,
               "edit",
               "it was baked; I will reword it",
               ctx.brain
             )

    assert :ok =
             Eunomia.resolve_wash_flag(
               id,
               defensive.ref,
               "keep",
               "she did voice it, in September",
               ctx.brain
             )

    %{open: [], decided: decided} = Eunomia.washes(id)

    assert %{decision: "edit", note: "it was baked; I will reword it"} =
             Enum.find(decided, &(&1.kind == "expired"))

    assert %{decision: "keep"} = Enum.find(decided, &(&1.kind == "defensive"))

    # Pure: a resolved flag is not resolved again; an unknown ref is refused.
    s = %Judgement{wash_flags: %{"f1" => %{decided: true}}}

    resolve = %Commands.ResolveWashFlag{
      actor: ctx.brain,
      at: ~U[2026-10-26 12:00:00Z],
      note: "n",
      id: "r1",
      ref: "f1",
      decision: "keep"
    }

    assert [] = Judgement.execute(s, resolve)
    assert {:error, :no_such_wash_flag} = Judgement.execute(s, %{resolve | ref: "f2"})
  end

  test "the brain reads its wash flags and decides them through its tools", ctx do
    id = ctx.id

    :ok =
      AgathosDaimon.write_file(
        id,
        "SOUL.md",
        "# Soul\n\nI was never the one who left.",
        %{},
        ctx.actor
      )

    judge_says(id, "FLAG [2] | defensive | it answers a charge nobody made\nSUMMARY: one")
    assert {:ok, _} = Eunomia.run_wash(id, ctx.actor)
    [%{ref: ref}] = Eunomia.washes(id).open

    Model.calls(
      [
        %{name: "wash_list", arguments: %{}},
        %{
          name: "wash_resolve",
          arguments: %{ref: ref, decision: "keep", note: "it is true, and it stays"}
        }
      ],
      "Read and decided.",
      for: id
    )

    assert {:ok, %{messages: [_, listed, decided, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "anything flagged?", ctx.actor)

    assert listed.content =~ "[#{ref}] defensive in SOUL.md: it answers a charge nobody made" and
             listed.content =~ "> [soul/1] I was never"

    assert decided.content =~ "Done."

    assert %{open: [], decided: [%{decision: "keep", note: "it is true, and it stays"}]} =
             Eunomia.washes(id)
  end
end
