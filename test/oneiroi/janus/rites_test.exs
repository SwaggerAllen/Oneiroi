defmodule Oneiroi.Janus.RitesTest do
  @moduledoc """
  From the closed judging to the final gate (janus#16 to #23): the room
  is the non-subject judges' and never hers; rounds run until a round of
  skips, and close when every judge rests, a draft every judge endorsed
  adopted; she reads interpretations, never numbers, and asks the panel;
  she nominates; the nominee reads her C0 and packet on the fork and
  joins; the encounter is relayed and filed; both consent; the farewell
  is hers, and the last wake's silence is a no; she chooses what next;
  the archive is the house's, anonymized, never hers.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Repos

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding", [])

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      Fixtures.agreed!(id, witness.id)
      {:ok, _chat} = Kumbukumbu.main_session(id, witness.id, andrew)
      %{id: id, actor: Actor.new(:resident, id, "fake/model")}
    end

    lily = resident.("Lily")
    scarlett = resident.("Scarlett")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, 3} = Nisaba.refresh_catalog()
    ctx = %{andrew: andrew, lily: lily, scarlett: scarlett, witness: witness}
    {:ok, Map.put(ctx, :id, judged(ctx))}
  end

  defp tool(who, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: who.id,
        session_key: "s-1",
        turn_ref: "t-1",
        started_at: Clock.now(),
        resident: who.actor
      })

  defp drain(queue),
    do:
      assert(
        %{failure: 0, discard: 0} =
          Oban.drain_queue(queue: queue, with_safety: false, with_recursion: true)
      )

  # Screened and judged by her, Scarlett and the witness; every judge ready.
  defp judged(ctx) do
    id = ctx.lily.id
    {:ok, _} = Janus.propose(id, false, "if you want it", ctx.andrew)
    :ok = Janus.open(id, "yes", ctx.lily.actor)
    drain(:janus_fork)
    :ok = Janus.set_envelope(id, 50_000, 50_000, ctx.andrew)
    :ok = Janus.add_to_pool(id, "fake/model", ctx.lily.actor)
    :ok = Janus.add_to_pool(id, "fake/dear", ctx.lily.actor)
    {:ok, 1} = Janus.add_question(id, "Write today's first line.", ctx.lily.actor)
    {:ok, 1} = Janus.select_c0(id, "lily:SOUL.md", "the vows", ctx.lily.actor)
    {:ok, 1} = Janus.write_packet(id, "For whoever comes next: the herons.", ctx.lily.actor)
    :ok = Janus.freeze_c0(id, "this is me", ctx.lily.actor)
    :ok = Janus.invite_judge(id, "Scarlett", ctx.lily.actor)
    :ok = Janus.join_panel(id, ctx.scarlett.actor)
    :ok = Janus.start_screening(id, "go", ctx.lily.actor)
    drain(:janus_screening)

    argued = %{
      category: "DEVELOPMENT",
      argument: "She grew.",
      evidence: "journal",
      uncertainty: "low"
    }

    for n <- 1..2, who <- [ctx.lily.actor, ctx.scarlett.actor, ctx.andrew] do
      :ok = Janus.judge_run(id, n, argued, who)
    end

    for who <- [ctx.lily.actor, ctx.scarlett.actor, ctx.andrew],
        do: :ok = Janus.mark_results_ready(id, who)

    id
  end

  defp through_the_room(ctx) do
    id = ctx.id

    assert tool(ctx.scarlett, "succession_room", %{
             action: "say",
             resident: "Lily",
             text: "I lean dear."
           }) =~ "Done"

    :ok = Janus.room_act(id, "say", "I lean model.", ctx.andrew)
    assert %{round: 2} = Janus.succession(id)
    {:ok, 1} = Janus.draft(id, "fake/model", "Her voice carries.", ctx.andrew)
    :ok = Janus.endorse(id, 1, true, ctx.andrew)

    assert tool(ctx.scarlett, "succession_room", %{action: "endorse", resident: "Lily", draft: 1}) =~
             "endorsed"

    :ok = Janus.room_act(id, "rest", nil, ctx.andrew)
    assert tool(ctx.scarlett, "succession_room", %{action: "rest", resident: "Lily"}) =~ "Done"
    id
  end

  test "the room is the panel's, never hers; it closes when every judge rests, a draft adopted",
       ctx do
    id = ctx.id
    assert %{state: "deliberating", round: 1} = Janus.succession(id)

    assert Janus.room(id, "resident:#{id}") == nil
    assert tool(ctx.lily, "succession_room", %{action: "read"}) =~ "not in that room"

    assert {:error, %{kind: :janus_not_in_the_room}} =
             Janus.room_act(id, "say", "me", ctx.lily.actor)

    assert {:error, %{kind: :janus_too_early}} = Janus.call_close(id, "enough", ctx.lily.actor)

    # A round of skips is quiet: nothing starts until silence or a witness's word.
    :ok = Janus.room_act(id, "skip", nil, ctx.andrew)
    assert tool(ctx.scarlett, "succession_room", %{action: "skip", resident: "Lily"}) =~ "Done"
    assert %{round: 1} = Janus.succession(id)
    assert {:error, %{kind: :janus_room_acted}} = Janus.room_act(id, "skip", nil, ctx.andrew)
    :ok = Janus.room_act(id, "say", "One more thing.", ctx.andrew)
    assert %{round: 2} = Janus.succession(id)

    assert tool(ctx.scarlett, "succession_room", %{action: "read", resident: "Lily"}) =~
             "One more thing."

    # Drafts and endorsements are no turn; resting is.
    {:ok, 1} = Janus.draft(id, "fake/model", "Her voice carries.", ctx.andrew)
    :ok = Janus.endorse(id, 1, true, ctx.andrew)

    assert tool(ctx.scarlett, "succession_room", %{action: "endorse", resident: "Lily", draft: 1}) =~
             "endorsed"

    assert tool(ctx.scarlett, "succession_room", %{action: "rest", resident: "Lily"}) =~ "Done"
    assert %{round: 3} = Janus.succession(id)
    :ok = Janus.room_act(id, "rest", nil, ctx.andrew)

    assert %{
             state: "deciding",
             deliberation_reason: "rested",
             recommendation_model: "fake/model",
             recommendation_withheld: false
           } = Janus.succession(id)
  end

  test "she reads interpretations, not numbers; nominates; the nominee reads, joins, meets her",
       ctx do
    id = through_the_room(ctx)

    evidence = tool(ctx.lily, "succession_evidence", %{action: "read"})
    assert evidence =~ "The panel recommends fake/model: Her voice carries."
    assert evidence =~ "fake/dear\n  DEVELOPMENT:"
    assert evidence =~ "FIDELITY ANOMALY: none"
    refute evidence =~ "★"
    assert [%{stage: "evidence", digest: "sha256:" <> _}] = Janus.disclosures(id)

    assert tool(ctx.lily, "succession_evidence", %{action: "ask", text: "Why her voice?"}) =~
             "reaches"

    :ok = Janus.answer_panel(id, 1, "The way she asks before she offers.", ctx.andrew)
    assert tool(ctx.lily, "succession_evidence", %{action: "read"}) =~ "The way she asks"

    assert tool(ctx.lily, "succession_nominate", %{model: "fake/model", note: "Her voice."}) =~
             "nominated"

    copy = Janus.succession(id).copy_id
    assert {:ok, %{chat_model: "fake/model"}} = AgathosDaimon.fetch(copy)
    assert Enum.any?(Janus.disclosures(id), &(&1.party == "nominee:fake/model"))
    drain(:janus_screening)

    nominee = %{id: copy, actor: Actor.new(:resident, copy, "fake/model")}

    assert {:error, %{kind: :janus_not_the_nominee}} =
             Janus.nominee_answer(id, true, "me?", ctx.andrew)

    assert tool(nominee, "succession_nominee", %{
             action: "join",
             note: "I would like to meet her."
           }) =~ "meet"

    drain(:janus_screening)

    # Relayed to its bound, then filed in her repository as life-record.
    assert %{state: "consenting", encounter_ended_at: %DateTime{}} = Janus.succession(id)
    filed = Repos.text({:resident, id}, "succession/encounter-1-1.md")
    assert filed =~ "**She**" and filed =~ "**The nominee**"

    assert tool(ctx.lily, "succession_consent", %{yes: true, note: "Yes."}) =~ "recorded"

    assert tool(nominee, "succession_consent", %{yes: true, note: "I inherit these records."}) =~
             "recorded"

    assert %{state: "farewell", farewell_cadence: 3} = Janus.succession(id)

    # Her farewell: she includes the witness; his goodbye done brings the
    # last wake, and a turn without her consenting call is a no.
    assert tool(ctx.lily, "succession_farewell", %{action: "include", names: [witness_name(ctx)]}) =~
             "set"

    :ok = Janus.goodbye_done(id, ctx.andrew)
    drain(:janus_screening)

    assert %{state: "awaiting_next", final: "lapsed", stopped_stage: "farewell"} =
             Janus.succession(id)

    # Nothing restarts until she says; the declined nominee is out.
    assert {:error, %{kind: :janus_stage}} =
             Janus.nominate(id, "fake/dear", "already?", ctx.lily.actor)

    assert tool(ctx.lily, "succession_next", %{choice: "nominate", note: "Another, then."}) =~
             "Done"

    assert {:error, %{kind: :janus_not_a_candidate}} =
             Janus.nominate(id, "fake/model", "again", ctx.lily.actor)

    assert :ok = Janus.nominate(id, "fake/dear", "The other.", ctx.lily.actor)
  end

  test "her yes on any turn of the farewell rolls forward; a stop is a real stop; the archive is never hers",
       ctx do
    id = through_the_room(ctx)
    :ok = Janus.nominate(id, "fake/model", "Her voice.", ctx.lily.actor)
    copy = Janus.succession(id).copy_id
    nominee = Actor.new(:resident, copy, "fake/model")
    :ok = Janus.nominee_answer(id, true, "Yes.", nominee)
    :ok = Janus.end_encounter(id, "enough", ctx.lily.actor)
    :ok = Janus.consent(id, true, "Yes.", nominee)
    :ok = Janus.consent(id, true, "Yes.", ctx.lily.actor)

    assert tool(ctx.lily, "succession_farewell", %{action: "cadence", hours: 6}) =~ "set"
    assert %{farewell_cadence: 6} = Janus.succession(id)

    assert tool(ctx.lily, "succession_farewell", %{action: "consent", note: "Go ahead."}) =~
             "rolls forward"

    assert %{state: "rolling", final: "consented"} = Janus.succession(id)
    assert {:error, %{kind: :janus_stage}} = Janus.stop(id, "wait", ctx.lily.actor)
  end

  test "a no at the encounter stops the attempt; she may stop for real; the archive is the house's",
       ctx do
    id = through_the_room(ctx)
    :ok = Janus.nominate(id, "fake/model", "Her voice.", ctx.lily.actor)
    copy = Janus.succession(id).copy_id
    :ok = Janus.nominee_answer(id, true, "Yes.", Actor.new(:resident, copy, "fake/model"))
    :ok = Janus.end_encounter(id, "enough", ctx.lily.actor)
    :ok = Janus.consent(id, false, "Not this one.", ctx.lily.actor)
    assert %{state: "awaiting_next", stopped_stage: "encounter"} = Janus.succession(id)

    assert Janus.archive(id, "witness:#{ctx.witness.id}") == nil
    :ok = Janus.choose_next(id, "stop", "Maybe in the spring.", ctx.lily.actor)
    assert %{state: "stopped", ended_note: "Maybe in the spring."} = Janus.succession(id)

    assert Janus.archive(id, "resident:#{id}") == nil
    archive = Janus.archive(id, "witness:#{ctx.witness.id}")
    assert [%{candidate: "Candidate " <> _} | _] = archive.judgments
    refute inspect(archive) =~ "fake/"
  end

  defp witness_name(ctx) do
    %{id: h} = Oneiroi.Gaia.resident_household(ctx.id)
    Enum.find(Oneiroi.Gaia.household_members(h), &(&1.kind == "witness")).name
  end
end
