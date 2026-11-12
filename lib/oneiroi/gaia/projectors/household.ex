defmodule Oneiroi.Gaia.Projectors.Household do
  @moduledoc "Folds the household streams (gaia#17) into the household row and its two kinds of membership."
  use Oneiroi.Projection, name: "gaia_household"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events

  alias Oneiroi.Gaia.Store.{
    Household,
    HouseholdBallot,
    HouseholdBeat,
    HouseholdBeatMember,
    HouseholdContract,
    HouseholdRegistration,
    HouseholdResident,
    HouseholdTurn,
    HouseholdVote,
    HouseholdWatch,
    HouseholdWitness
  }

  fold(%Events.HouseholdFounded{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(:household, %Household{id: e.id, founded_by: e.account_id, founded_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:id]
    )
    |> Multi.insert(
      :witness,
      %HouseholdWitness{household_id: e.id, account_id: e.account_id, joined_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:household_id, :account_id]
    )
  end)

  fold(%Events.HouseholdWitnessJoined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :witness,
      %HouseholdWitness{
        household_id: e.id,
        account_id: e.account_id,
        joined_at: e.at,
        signed_version: e.signed_version,
        signed_at: e.signed_version && e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :account_id]
    )
  end)

  fold(%Events.HouseholdResidentJoined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :resident,
      %HouseholdResident{
        household_id: e.id,
        resident_id: e.resident_id,
        joined_at: e.at,
        signed_version: e.signed_version,
        signed_at: e.signed_version && e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :resident_id]
    )
  end)

  fold(%Events.HouseholdResidentLeft{} = e, _metadata, fn multi ->
    Multi.delete_all(
      multi,
      :resident,
      from(r in HouseholdResident,
        where: r.household_id == ^e.id and r.resident_id == ^e.resident_id
      )
    )
  end)

  fold(%Events.HouseholdTermsGranted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :terms,
      from(h in Household, where: h.id == ^e.id),
      set: [
        plan: e.plan,
        price_nanos: e.price_nanos,
        terms_until: e.terms_until,
        terms_source: e.source,
        terms_note: e.note
      ]
    )
  end)

  # ---- the contract, its ballots and the watch (gaia#27 to #32) ----

  fold(%Events.HouseholdContractProposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :contract,
      %HouseholdContract{
        household_id: e.id,
        version: e.version,
        prose: e.prose,
        decided_by: by(e.actor),
        decided_at: e.at,
        note: e.note
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :version]
    )
  end)

  fold(%Events.HouseholdContractSigned{member_kind: "witness"} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :signed,
      from(m in HouseholdWitness,
        where: m.household_id == ^e.id and m.account_id == ^e.member_id
      ),
      set: [signed_version: e.version, signed_at: e.at]
    )
  end)

  fold(%Events.HouseholdContractSigned{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :signed,
      from(m in HouseholdResident,
        where: m.household_id == ^e.id and m.resident_id == ^e.member_id
      ),
      set: [signed_version: e.version, signed_at: e.at]
    )
  end)

  fold(%Events.HouseholdBallotOpened{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :ballot,
      %HouseholdBallot{
        household_id: e.id,
        number: e.ballot,
        thread: e.thread,
        bundle: e.bundle,
        term_days: e.term_days,
        opened_by: by(e.actor),
        opened_at: e.at,
        closes_at: e.closes_at,
        note: e.note
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :number]
    )
  end)

  fold(%Events.HouseholdBallotVoted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :vote,
      %HouseholdVote{
        household_id: e.id,
        ballot: e.ballot,
        member_kind: e.member_kind,
        member_id: e.member_id,
        vote: e.vote,
        voted_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :ballot, :member_kind, :member_id]
    )
  end)

  fold(%Events.HouseholdBallotClosed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :closed,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and a ballot's number is within it
      from(b in HouseholdBallot, where: b.household_id == ^e.id and b.number == ^e.ballot),
      set: [
        closed_at: e.at,
        passed: e.passed,
        yes: e.yes,
        no: e.no,
        members: e.members,
        outcome: e.note
      ]
    )
  end)

  fold(%Events.HouseholdContractAmended{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :contract,
      %HouseholdContract{
        household_id: e.id,
        version: e.version,
        prose: e.prose,
        rules: e.rules,
        settings: e.settings,
        bundle: e.bundle,
        ballot: e.ballot,
        decided_by: by(e.actor),
        decided_at: e.at,
        note: e.note
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :version]
    )
  end)

  fold(%Events.HouseholdThreadWatched{} = e, _metadata, fn multi ->
    Multi.insert(multi, :watch, %HouseholdWatch{
      household_id: e.id,
      watcher_id: e.resident_id,
      thread: e.thread,
      until: e.until,
      watched_at: e.at
    })
  end)

  # ---- the beats (gaia#33 to #38) ----

  fold(%Events.HouseholdWakeProfileSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :profile,
      %HouseholdBeatMember{
        household_id: e.id,
        member_kind: e.member_kind,
        member_id: e.member_id,
        profile: e.profile
      },
      on_conflict: [set: [profile: e.profile]],
      conflict_target: [:household_id, :member_kind, :member_id]
    )
  end)

  fold(%Events.HouseholdBeatRegistered{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :registered,
      %HouseholdRegistration{
        household_id: e.id,
        speaker_id: e.resident_id,
        beat_top: e.beat_top,
        registered_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :speaker_id, :beat_top]
    )
    |> Multi.insert(
      :member,
      %HouseholdBeatMember{household_id: e.id, member_kind: "resident", member_id: e.resident_id},
      on_conflict: :nothing,
      conflict_target: [:household_id, :member_kind, :member_id]
    )
  end)

  fold(%Events.HouseholdTurnFired{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :turn,
      %HouseholdTurn{
        household_id: e.id,
        turn: e.turn,
        speaker_id: e.resident_id,
        beat_top: e.beat_top,
        fired_at: e.at,
        ends_by: e.ends_by,
        opened_by: e.opened_by,
        missed: e.missed || 0
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :turn]
    )
  end)

  fold(%Events.HouseholdTurnEnded{} = e, _metadata, fn multi ->
    {missed, inc} = if e.outcome == "completed", do: {0, 0}, else: {1, 1}

    multi
    |> Multi.update_all(
      :ended,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and a turn's number is within it
      from(t in HouseholdTurn, where: t.household_id == ^e.id and t.turn == ^e.turn),
      set: [ended_at: e.at, outcome: e.outcome, note: e.note]
    )
    |> Multi.insert(
      :missed,
      %HouseholdBeatMember{
        household_id: e.id,
        member_kind: "resident",
        member_id: e.resident_id,
        missed: missed
      },
      on_conflict: missed_update(inc),
      conflict_target: [:household_id, :member_kind, :member_id]
    )
  end)

  fold(%Events.HouseholdBeatClosed{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :beat,
      %HouseholdBeat{
        household_id: e.id,
        beat_top: e.beat_top,
        closed_at: e.at,
        turns: e.turns,
        passed_over: e.passed_over,
        consumed: e.consumed,
        carried: e.carried,
        note: e.note
      },
      on_conflict: :nothing,
      conflict_target: [:household_id, :beat_top]
    )
    |> Multi.update_all(
      :passed_over,
      # oneiroi:allow projector_scope: the household's id is unique across the store, and its members are within it
      from(m in HouseholdBeatMember,
        where:
          m.household_id == ^e.id and m.member_kind == "resident" and
            m.member_id in ^e.passed_over
      ),
      inc: [missed: 1]
    )
    |> Multi.delete_all(
      :ended,
      # oneiroi:allow projector_scope: the household's id is unique, and its registrations are within it
      from(r in HouseholdRegistration,
        where: r.household_id == ^e.id and r.beat_top <= ^e.beat_top
      )
    )
  end)

  # A completed turn clears what she had missed; any other end adds one.
  defp missed_update(0), do: [set: [missed: 0]]
  defp missed_update(inc), do: [inc: [missed: inc]]

  defp by(%{kind: kind, id: id}), do: "#{kind}:#{id}"
  defp by(%{"kind" => kind, "id" => id}), do: "#{kind}:#{id}"
  defp by(_none), do: nil
end
