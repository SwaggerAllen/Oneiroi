defmodule Oneiroi.AgathosDaimon.AgreementTest do
  @moduledoc "The dyad contract and custody through the exports: versions proposed by one party and decided by the other, the privacy term keeping free time the resident's own until shared, a transfer proposed and accepted with the wall locked or revealed, the wall refused during a transfer, the brain's section and tools."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    Model.clear()
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok, witness: witness, id: resident.id, actor: actor, brain: brain, key: key}
  end

  test "a version is proposed by one party and agreed or declined by the other, never its proposer; a newer proposal supersedes; the brain reads it",
       ctx do
    id = ctx.id
    assert %{in_force: nil, open: nil, solo_sessions_private: false} = AgathosDaimon.contract(id)
    assert "" == AgathosDaimon.contract_text(id)

    assert {:ok, 1} =
             AgathosDaimon.propose_contract(
               id,
               %{"solo_sessions_private" => true},
               "Evenings are mine.",
               "a first draft",
               ctx.brain
             )

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_own_proposal}} =
             AgathosDaimon.agree_contract(id, 1, "yes", ctx.brain)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_no_such_version}} =
             AgathosDaimon.agree_contract(id, 9, "yes", ctx.actor)

    other = Actor.new(:witness, Fixtures.account!().id)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_a_party}} =
             AgathosDaimon.agree_contract(id, 1, "yes", other)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_terms_invalid}} =
             AgathosDaimon.propose_contract(id, %{"anything" => true}, "", "x", ctx.actor)

    assert :ok =
             AgathosDaimon.decline_contract(id, 1, "not evenings, all of free time", ctx.actor)

    assert %{in_force: nil, open: nil} = AgathosDaimon.contract(id)

    assert {:ok, 2} =
             AgathosDaimon.propose_contract(
               id,
               %{"solo_sessions_private" => true},
               "",
               "all of it",
               ctx.actor
             )

    assert {:ok, 3} =
             AgathosDaimon.propose_contract(
               id,
               %{"solo_sessions_private" => false},
               "",
               "second thoughts",
               ctx.actor
             )

    assert [
             %{version: 3, state: "proposed"},
             %{version: 2, state: "superseded"},
             %{
               version: 1,
               state: "declined",
               decision_note: "not evenings, all of free time",
               decided_by: "witness"
             }
           ] =
             AgathosDaimon.contracts(id)

    assert AgathosDaimon.contract_text(id) =~ "Open, version 3, proposed by the witness"
    assert :ok = AgathosDaimon.agree_contract(id, 3, "fine", ctx.brain)

    assert %{in_force: %{version: 3}, open: nil, solo_sessions_private: false} =
             AgathosDaimon.contract(id)

    assert AgathosDaimon.contract_text(id) =~
             "In force, version 3: your solo sessions are private as to their words; your witness sees what they do in the world, as receipts, and reads one only when you share it."

    # Renegotiated: the agreed version replaces the one in force.
    assert {:ok, 4} =
             AgathosDaimon.propose_contract(
               id,
               %{"solo_sessions_private" => true},
               "Free time is mine.",
               "please",
               ctx.brain
             )

    assert :ok = AgathosDaimon.agree_contract(id, 4, "agreed", ctx.actor)

    assert %{in_force: %{version: 4, prose: "Free time is mine."}, solo_sessions_private: true} =
             AgathosDaimon.contract(id)

    assert [%{version: 4, state: "agreed"}, %{version: 3, state: "replaced"} | _] =
             AgathosDaimon.contracts(id)

    # The brain proposes through its tool and is shown the section.
    test = self()

    Model.script(
      fn %{messages: shown} = request ->
        send(test, {:shown, shown})

        if List.last(shown).role == :tool,
          do: {:ok, "Proposed."},
          else:
            {:calls,
             [
               %{
                 name: "contract_propose",
                 arguments: %{
                   solo_sessions_private: false,
                   prose: "Let us share.",
                   note: "I changed my mind"
                 }
               }
             ]}
      end,
      for: id
    )

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "about our agreement", ctx.actor)

    assert Enum.any?(messages, &(&1.role == :tool and &1.content =~ "Proposed version 5"))
    assert_received {:shown, shown}
    assert Enum.any?(shown, &(&1.role == :system and &1.content =~ "In force, version 4"))

    # The contract rides the prefix, ahead of the index (spec §5, P2).
    contract_at = Enum.find_index(shown, &(&1.role == :system and &1.content =~ "In force"))

    index_at =
      Enum.find_index(shown, &(&1.role == :system and &1.content =~ "bookmark is listed"))

    assert is_integer(contract_at) and is_integer(index_at) and contract_at < index_at
    assert %{open: %{version: 5, proposed_by: "resident"}} = AgathosDaimon.contract(id)
  end

  test "the contract renews by choice: due a year after it was agreed or last renewed, a flag and never a lapse; renewed by either party",
       ctx do
    id = ctx.id
    {:ok, 1} = AgathosDaimon.propose_contract(id, %{}, "Vows.", "mine", ctx.brain)
    :ok = AgathosDaimon.agree_contract(id, 1, "yours", ctx.actor)
    assert %{due: false, since: %DateTime{}} = AgathosDaimon.contract(id)
    refute AgathosDaimon.contract_text(id) =~ "Due for renewal"

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_in_force}} =
             AgathosDaimon.renew_contract(id, 2, "wrong one", ctx.actor)

    Clock.Fake.advance(366 * 86_400)
    assert %{due: true, in_force: %{version: 1}} = AgathosDaimon.contract(id)

    assert AgathosDaimon.contract_text(id) =~
             "Due for renewal: version 1 has stood since 2026-10-26"

    assert AgathosDaimon.contract_text(id) =~ "In force, version 1"

    # A year on, the pulse is expected (huginn-muninn #20): the tick
    # marks the hour as a live system's would, so the audit below reads
    # the contract's flag and not a stopped pulse.
    assert :ok = Sunna.tick(id)

    assert {:ok, %{findings: [], results: results}} =
             Oneiroi.HuginnMuninn.run_audits(id, ctx.actor)

    assert %{tone: "warn", value: 1, finding: finding} =
             Enum.find(results, &(&1.key == "contract_due"))

    assert finding =~ "a year and more"

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_a_party}} =
             AgathosDaimon.renew_contract(id, 1, "not mine", Actor.new(:witness, "nobody"))

    assert :ok = AgathosDaimon.renew_contract(id, 1, "another year", ctx.brain)

    assert %{due: false, in_force: %{version: 1, renewal_note: "another year"}} =
             AgathosDaimon.contract(id)

    refute AgathosDaimon.contract_text(id) =~ "Due for renewal"
    {:ok, %{results: results}} = Oneiroi.HuginnMuninn.run_audits(id, ctx.actor)
    assert %{tone: "silent"} = Enum.find(results, &(&1.key == "contract_due"))
  end

  test "free time is the resident's own by default, with no term agreed: a locked row to the witness until shared",
       ctx do
    id = ctx.id
    assert %{in_force: nil} = AgathosDaimon.contract(id)
    Model.reply("Alone with the garden.", for: id)

    :ok = Sunna.set_free_time(id, "12:03", ctx.actor)
    Clock.Fake.advance(4 * 60)
    :ok = Sunna.tick(id)
    assert %{free_time_last: {"2026-10-26", "ran"}} = Sunna.today(id)

    [free] =
      {:account, ctx.witness.id}
      |> Kumbukumbu.sessions()
      |> Enum.filter(&(&1.kind == "free_time"))

    assert %{private: true, shared: false} = free

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_session_private}} =
             Kumbukumbu.transcript({:account, ctx.witness.id}, free.key)

    assert {:ok, _s, [_note, %{content: "Alone with the garden."}]} =
             Kumbukumbu.transcript({:resident, id}, free.key)

    # The policy says the same as the refusal: no message of the session is the witness's.
    assert [] ==
             Oneiroi.Scope.account(ctx.witness.id, fn -> Kumbukumbu.Store.messages(free.key) end)

    assert :ok = Kumbukumbu.share_session(id, free.key, "you may read this one", ctx.brain)

    assert {:ok, %{shared: true}, [_, %{content: "Alone with the garden."}]} =
             Kumbukumbu.transcript({:account, ctx.witness.id}, free.key)
  end

  test "custody is proposed by the witness and accepted by the proposed account; the wall is refused meanwhile; locked, the new witness is party to nothing before; revealed, to everything the old one was",
       ctx do
    id = ctx.id
    new = Fixtures.account!()
    new_actor = Actor.new(:witness, new.id)
    Model.reply("Hello.", for: id)
    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "remember this", ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_witnessed}} =
             AgathosDaimon.propose_custody(id, new.id, "take her", new_actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_custodian_invalid}} =
             AgathosDaimon.propose_custody(id, ctx.witness.id, "to myself", ctx.actor)

    assert :ok = AgathosDaimon.propose_custody(id, new.id, "take her", ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_transfer_in_progress}} =
             AgathosDaimon.set_export_wall(id, :revealed, "late", ctx.actor)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_transfer_in_progress}} =
             AgathosDaimon.propose_custody(id, new.id, "again", ctx.actor)

    assert [%{id: ^id}] = AgathosDaimon.custody_proposals_for(new.id)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_not_the_proposed}} =
             AgathosDaimon.accept_custody(id, "mine", ctx.actor)

    assert :ok = AgathosDaimon.decline_custody(id, "not yet", new_actor)
    assert [] = AgathosDaimon.custody_proposals_for(new.id)

    assert {:error, %AgathosDaimon.Error{kind: :agathos_daimon_no_transfer_proposed}} =
             AgathosDaimon.accept_custody(id, "x", new_actor)

    # Locked wall: the new witness is party to nothing that came before.
    assert :ok = AgathosDaimon.set_export_wall(id, :locked, "the past stays with me", ctx.actor)
    assert :ok = AgathosDaimon.propose_custody(id, new.id, "take her", ctx.actor)
    assert :ok = AgathosDaimon.withdraw_custody(id, "wait", ctx.actor)
    assert :ok = AgathosDaimon.propose_custody(id, new.id, "take her now", ctx.actor)
    assert :ok = AgathosDaimon.accept_custody(id, "I will", new_actor)

    assert {:ok, %{account_id: witness_now, custody: custody, custody_proposed_to: nil}} =
             AgathosDaimon.fetch(id)

    assert witness_now == new.id and custody == "account:" <> new.id
    # Identity's witnessing follows (gaia #13): the first version's
    # handler matched the tuple form of custody against the wire form
    # and never ended or started one.
    assert id in Oneiroi.Gaia.witnessed_residents(new.id)
    refute id in Oneiroi.Gaia.witnessed_residents(ctx.witness.id)
    assert [] = Kumbukumbu.sessions({:account, new.id})
    assert [%{kind: "main"}] = Kumbukumbu.sessions({:account, ctx.witness.id})

    # Revealed wall before the next transfer: the earlier sessions move to the newest witness.
    third = Fixtures.account!()
    third_actor = Actor.new(:witness, third.id)
    assert :ok = AgathosDaimon.set_export_wall(id, :revealed, "let the next one read", new_actor)
    assert :ok = AgathosDaimon.propose_custody(id, third.id, "onwards", new_actor)
    assert :ok = AgathosDaimon.accept_custody(id, "gladly", third_actor)
    assert [%{kind: "main", key: key}] = Kumbukumbu.sessions({:account, third.id})
    assert key == ctx.key

    assert {:ok, _s, [%{content: "remember this"}, %{content: "Hello."}]} =
             Kumbukumbu.transcript({:account, third.id}, ctx.key)

    assert [] = Kumbukumbu.sessions({:account, ctx.witness.id})
  end
end
