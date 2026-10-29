defmodule Oneiroi.Eunomia.MemoryAuditTest do
  @moduledoc "The weekly memory audit: the judge over Honcho's conclusions against positions and the soul; flags approved (the conclusion leaves Honcho) or deleted (it stays), with a note; a reply naming an unknown number fails."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Eunomia
  alias Oneiroi.Eunomia.AuditWorker
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  @since ~U[2026-10-01 00:00:00.000000Z]

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    actor = Actor.new(:steward, steward.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", actor)

    :ok =
      AgathosDaimon.write_file(
        resident.id,
        "SOUL.md",
        "# Soul\n\nTakes people at their word.",
        %{},
        actor
      )

    {:ok, key} = Kumbukumbu.main_session(resident.id, steward.id, actor)
    :ok = Proteus.provision(resident.id, actor)
    Model.clear()
    Honcho.clear(for: resident.id)
    :ok = Proteus.provision(resident.id, actor)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok, steward: steward, id: resident.id, actor: actor, brain: brain, key: key}
  end

  defp seed(ctx, conclusions) do
    Honcho.put_conclusions(
      ctx.id,
      "resident-" <> ctx.id,
      "steward-" <> ctx.steward.id,
      conclusions
    )
  end

  defp judge_says(id, text), do: Model.script(fn _request -> {:ok, text} end, for: id)

  test "the audit flags drift against positions and the soul; the steward approves or deletes each flag with a note; nothing concluded calls no model",
       ctx do
    id = ctx.id

    {:ok, 1} =
      Eunomia.take_position(
        id,
        "She loves tea.",
        %{session_key: ctx.key, turn_ref: "t1"},
        ctx.brain
      )

    # Nothing concluded yet: no call, a run of zero.
    assert {:ok, _} = Eunomia.run_audit(id, ctx.actor)

    assert %{runs: [%{conclusions: 0, flagged: 0, judge_model: nil}], open: []} =
             Eunomia.audits(id)

    assert [] = Nisaba.spend(id, :steward, :purpose, @since)

    seed(ctx, [
      %{id: "c1", content: "She hates tea."},
      %{id: "c2", content: "She lives in Leeds."}
    ])

    test = self()

    Model.script(
      fn %{messages: [%{content: prompt} | _]} ->
        send(test, {:prompt, prompt})

        {:ok,
         "FLAG [1] | contradicts position #1, which she took in conversation\nSUMMARY: one hardened remark"}
      end,
      for: id
    )

    assert {:ok, ref} = Eunomia.run_audit(id, ctx.actor)
    assert_received {:prompt, prompt}

    assert prompt =~ "#1 She loves tea." and prompt =~ "Takes people at their word." and
             prompt =~ "[2] She lives in Leeds."

    assert %{runs: runs, open: [flag]} = Eunomia.audits(id)

    assert %{
             conclusions: 2,
             flagged: 1,
             judge_model: "fake/judge",
             summary: "one hardened remark"
           } =
             Enum.find(runs, &(&1.ref == ref))

    assert %{
             conclusion_id: "c1",
             conclusion: "She hates tea.",
             reason: "contradicts position #1" <> _
           } = flag

    assert [%{key: "judge", calls: 1}] = Nisaba.spend(id, :steward, :purpose, @since)

    assert {:error, %Eunomia.Error{kind: :eunomia_not_the_steward}} =
             Eunomia.approve_flag(id, flag.ref, "agreed", ctx.brain)

    assert :ok = Eunomia.approve_flag(id, flag.ref, "she said so herself", ctx.actor)
    assert {:ok, [%{id: "c2"}]} = Proteus.conclusions(id, 150)

    assert {:error, %Eunomia.Error{kind: :eunomia_flag_decided}} =
             Eunomia.approve_flag(id, flag.ref, "again", ctx.actor)

    assert {:error, %Eunomia.Error{kind: :eunomia_no_such_flag}} =
             Eunomia.delete_flag(id, "zz", "x", ctx.actor)

    judge_says(id, "FLAG [1] | overreach from one remark\nSUMMARY: fine")
    assert {:ok, _} = Eunomia.run_audit(id, ctx.actor)
    %{open: [flag2]} = Eunomia.audits(id)
    assert flag2.conclusion_id == "c2"
    assert :ok = Eunomia.delete_flag(id, flag2.ref, "she does live there", ctx.actor)
    assert {:ok, [%{id: "c2"}]} = Proteus.conclusions(id, 150)

    # Raised at one instant under the fixed clock, so the order is by ref.
    assert %{open: [], decided: decided} = Eunomia.audits(id)
    assert %{note: "she said so herself"} = Enum.find(decided, &(&1.decision == "approved"))
    assert Enum.any?(decided, &(&1.decision == "deleted"))

    judge_says(id, "FLAG [9] | nonsense\nSUMMARY: x")

    assert {:error, %Eunomia.Error{kind: :eunomia_audit_failed}} =
             Eunomia.run_audit(id, ctx.actor)

    assert %{runs: runs} = Eunomia.audits(id)
    assert %{reason: reason} = Enum.find(runs, &(&1.outcome == "failed"))
    assert reason =~ "flagged conclusion 9"
  end

  test "the weekly job audits every active resident with a workspace", ctx do
    seed(ctx, [%{id: "c1", content: "She hates tea."}])
    judge_says(ctx.id, "SUMMARY: nothing to flag")
    other = Fixtures.resident!(Fixtures.account!())
    Oneiroi.Scope.resident(other.id, fn -> :ok end)
    :ok = Oneiroi.Scope.put(:platform)
    assert :ok = AuditWorker.run(%{})
    assert %{runs: [%{conclusions: 1, flagged: 0}]} = Eunomia.audits(ctx.id)
    assert %{runs: []} = Eunomia.audits(other.id)
  end
end
