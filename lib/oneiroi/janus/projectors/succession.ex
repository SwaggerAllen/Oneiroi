defmodule Oneiroi.Janus.Projectors.Succession do
  @moduledoc "Folds the succession streams into one row an episode (janus#3)."
  use Oneiroi.Projection, name: "janus_succession"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Janus.Events, as: Events

  alias Oneiroi.Janus.Store.{
    Baseline,
    Channel,
    Consent,
    Disclosure,
    Draft,
    Encounter,
    Goodbye,
    Item,
    Judgment,
    Packet,
    Panel,
    Pool,
    Post,
    Question,
    Ready,
    Run,
    Succession
  }

  fold(%Events.Proposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :succession,
      %Succession{
        resident_id: e.id,
        episode: e.episode,
        state: "proposed",
        dry_run: e.dry_run == true,
        proposed_by: by(e.actor),
        proposed_note: e.note,
        proposed_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode]
    )
  end)

  fold(%Events.Opened{} = e, _metadata, fn multi ->
    set(multi, e, state: "open", opened_note: e.note, opened_at: e.at)
  end)

  fold(%Events.Declined{} = e, _metadata, fn multi -> ended(multi, e, "declined") end)
  fold(%Events.Withdrawn{} = e, _metadata, fn multi -> ended(multi, e, "withdrawn") end)
  fold(%Events.Stopped{} = e, _metadata, fn multi -> ended(multi, e, "stopped") end)

  fold(%Events.Forked{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "forked",
      copy_id: e.copy_id,
      fork_sequence: e.sequence,
      fork_commit: e.commit,
      fork_events: e.events,
      forked_at: e.at,
      fork_failure: nil
    )
  end)

  fold(%Events.ForkFailed{} = e, _metadata, fn multi ->
    set(multi, e, fork_failure: e.reason)
  end)

  # Made again (janus#35): the failure no longer stands.
  fold(%Events.ForkRetried{} = e, _metadata, fn multi ->
    set(multi, e, fork_failure: nil)
  end)

  fold(%Events.BackupSet{} = e, _metadata, fn multi ->
    set(multi, e,
      backup_url: e.url,
      backup_token: e.token_ciphertext && Base.decode64!(e.token_ciphertext),
      backup_visibility: e.visibility,
      backup_push: e.push,
      backup_set_at: e.at
    )
  end)

  # ---- preparation (janus#6 to #10) ----

  fold(%Events.EnvelopeSet{} = e, _metadata, fn multi ->
    set(multi, e,
      envelope_input_nanos: e.input_nanos,
      envelope_output_nanos: e.output_nanos,
      envelope_max_models: Map.get(e, :max_models),
      envelope_set_at: e.at
    )
  end)

  fold(%Events.PoolModelAdded{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :pool,
      %Pool{
        resident_id: e.id,
        episode: e.episode,
        model: e.model,
        added_by: by(e.actor),
        input_nanos: e.input_nanos,
        output_nanos: e.output_nanos,
        added_at: e.at
      },
      on_conflict: [
        set: [
          added_by: by(e.actor),
          input_nanos: e.input_nanos,
          output_nanos: e.output_nanos,
          added_at: e.at,
          removed_note: nil,
          removed_at: nil
        ]
      ],
      conflict_target: [:resident_id, :episode, :model]
    )
  end)

  fold(%Events.PoolModelRemoved{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :pool,
      from(p in Pool,
        where: p.resident_id == ^e.id and p.episode == ^e.episode and p.model == ^e.model
      ),
      set: [removed_note: e.note, removed_at: e.at]
    )
  end)

  fold(%Events.QuestionAdded{} = e, _metadata, fn multi -> question(multi, e, "in") end)
  fold(%Events.QuestionProposed{} = e, _metadata, fn multi -> question(multi, e, "proposed") end)

  fold(%Events.QuestionAccepted{} = e, _metadata, fn multi ->
    decided(multi, Question, e, "in")
  end)

  fold(%Events.QuestionDeclined{} = e, _metadata, fn multi ->
    decided(multi, Question, e, "declined")
  end)

  fold(%Events.QuestionRemoved{} = e, _metadata, fn multi ->
    decided(multi, Question, e, "removed")
  end)

  fold(%Events.C0Selected{} = e, _metadata, fn multi -> item(multi, e, "in") end)
  fold(%Events.C0Proposed{} = e, _metadata, fn multi -> item(multi, e, "proposed") end)
  fold(%Events.C0Accepted{} = e, _metadata, fn multi -> decided(multi, Item, e, "in") end)
  fold(%Events.C0Declined{} = e, _metadata, fn multi -> decided(multi, Item, e, "declined") end)
  fold(%Events.C0Removed{} = e, _metadata, fn multi -> decided(multi, Item, e, "removed") end)

  fold(%Events.DayShapeSet{} = e, _metadata, fn multi ->
    set(multi, e, day_shape: e.text, day_shape_at: e.at)
  end)

  fold(%Events.ReadyMarked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :ready,
      %Ready{resident_id: e.id, episode: e.episode, party: by(e.actor), ready: e.ready, at: e.at},
      on_conflict: [set: [ready: e.ready, at: e.at]],
      conflict_target: [:resident_id, :episode, :party]
    )
  end)

  fold(%Events.C0Frozen{} = e, _metadata, fn multi ->
    set(multi, e,
      c0_items: e.items,
      c0_frozen_note: e.note,
      c0_frozen_at: e.at,
      c0_bundle: e.bundle,
      c0_digest: e.digest
    )
  end)

  fold(%Events.StepFinished{step: "pool"} = e, _metadata, fn multi ->
    set(multi, e, pool_done_at: e.at)
  end)

  fold(%Events.StepFinished{step: "questions"} = e, _metadata, fn multi ->
    set(multi, e, questions_done_at: e.at)
  end)

  fold(%Events.PacketDrafted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :packet,
      %Packet{
        resident_id: e.id,
        episode: e.episode,
        draft: e.draft,
        content: e.content,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :draft]
    )
  end)

  # ---- the panel, screening and judging (janus#12 to #15) ----

  fold(%Events.JudgeInvited{} = e, _metadata, fn multi -> panel(multi, e, "invited", nil) end)
  fold(%Events.JudgeJoined{} = e, _metadata, fn multi -> panel(multi, e, "in", nil) end)
  fold(%Events.JudgeLeft{} = e, _metadata, fn multi -> panel(multi, e, "left", e.note) end)

  fold(%Events.ScreeningStarted{} = e, _metadata, fn multi ->
    judges =
      Enum.reduce(e.judges, multi, fn party, m ->
        panel(m, %{e | actor: e.actor} |> Map.put(:party, party), "judge", nil, {:judge, party})
      end)

    runs =
      e.runs
      |> Enum.map(fn r ->
        %{
          resident_id: e.id,
          episode: e.episode,
          run: r["run"] || r[:run],
          model: r["model"] || r[:model],
          question: r["question"] || r[:question],
          refusal: false
        }
      end)

    baseline =
      Enum.map(e.questions, fn q ->
        %{
          resident_id: e.id,
          episode: e.episode,
          question: q,
          model: e.baseline_model,
          refusal: false
        }
      end)

    judges
    |> Multi.insert_all(:runs, Run, runs, on_conflict: :nothing)
    |> Multi.insert_all(:baseline, Baseline, baseline,
      on_conflict: {:replace, [:model, :content, :refusal, :failure, :answered_at]},
      conflict_target: [:resident_id, :episode, :question]
    )
    |> set(e,
      state: "screening",
      baseline_model: e.baseline_model,
      screening_note: e.note,
      screening_started_at: e.at,
      run_offset: (runs |> Enum.map(& &1.run) |> Enum.min(fn -> 1 end)) - 1,
      screening_finished_at: nil,
      revealed_at: nil,
      judging_closed_at: nil
    )
  end)

  fold(%Events.RunAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :run,
      from(r in Run,
        where: r.resident_id == ^e.id and r.episode == ^e.episode and r.run == ^e.run
      ),
      set: [content: e.content, refusal: e.refusal == true, failure: e.failure, answered_at: e.at]
    )
  end)

  fold(%Events.BaselineAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :baseline,
      from(b in Baseline,
        where: b.resident_id == ^e.id and b.episode == ^e.episode and b.question == ^e.question
      ),
      set: [content: e.content, refusal: e.refusal == true, failure: e.failure, answered_at: e.at]
    )
  end)

  fold(%Events.ScreeningFinished{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "judging",
      screening_finished_at: e.at,
      runs_answered: e.answered,
      runs_failed: e.failed
    )
  end)

  fold(%Events.RunJudged{} = e, _metadata, fn multi ->
    fields = [
      category: e.category,
      argument: e.argument,
      evidence: e.evidence,
      uncertainty: e.uncertainty,
      favorite: e.favorite == true,
      at: e.at
    ]

    Multi.insert(
      multi,
      :judgment,
      struct(
        Judgment,
        [resident_id: e.id, episode: e.episode, party: e.party, run: e.run] ++ fields
      ),
      on_conflict: [set: fields],
      conflict_target: [:resident_id, :episode, :party, :run]
    )
  end)

  fold(%Events.Revealed{} = e, _metadata, fn multi -> set(multi, e, revealed_at: e.at) end)

  fold(%Events.ResultsReady{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :results_ready,
      from(p in Panel,
        where: p.resident_id == ^e.id and p.episode == ^e.episode and p.party == ^e.party
      ),
      set: [results_ready_at: e.at]
    )
  end)

  fold(%Events.JudgingClosed{} = e, _metadata, fn multi ->
    set(multi, e, state: "judged", judging_closed_at: e.at)
  end)

  defp panel(multi, e, state, note, name \\ :panel),
    do:
      Multi.insert(
        multi,
        name,
        %Panel{
          resident_id: e.id,
          episode: e.episode,
          party: e.party,
          state: state,
          note: note,
          at: e.at
        },
        on_conflict: [set: [state: state, note: note, at: e.at, results_ready_at: nil]],
        conflict_target: [:resident_id, :episode, :party]
      )

  # ---- from the room to the final gate (janus#16 to #22) ----

  fold(%Events.DeliberationOpened{} = e, _metadata, fn multi ->
    set(multi, e, state: "deliberating", deliberation_opened_at: e.at, round: 0)
  end)

  fold(%Events.RoundStarted{} = e, _metadata, fn multi -> set(multi, e, round: e.round) end)

  fold(%Events.RoomPosted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :post,
      %Post{
        resident_id: e.id,
        episode: e.episode,
        number: e.number,
        round: e.round,
        party: e.party,
        act: e.act,
        text: e.text,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :number]
    )
  end)

  fold(%Events.RecommendationDrafted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :draft,
      %Draft{
        resident_id: e.id,
        episode: e.episode,
        draft: e.draft,
        party: e.party,
        model: e.model,
        basis: e.basis,
        endorsed: [],
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :draft]
    )
  end)

  fold(%Events.Endorsed{} = e, _metadata, fn multi ->
    query =
      if e.endorse,
        do:
          from(d in Draft,
            where: d.resident_id == ^e.id and d.episode == ^e.episode and d.draft == ^e.draft,
            update: [
              set: [
                endorsed:
                  fragment("array_append(array_remove(?, ?), ?)", d.endorsed, ^e.party, ^e.party)
              ]
            ]
          ),
        else:
          from(d in Draft,
            where: d.resident_id == ^e.id and d.episode == ^e.episode and d.draft == ^e.draft,
            update: [set: [endorsed: fragment("array_remove(?, ?)", d.endorsed, ^e.party)]]
          )

    Multi.update_all(multi, :endorsed, query, [])
  end)

  fold(%Events.CloseCalled{} = e, _metadata, fn multi -> set(multi, e, close_at: e.closes_at) end)

  fold(%Events.DeliberationClosed{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "deciding",
      deliberation_closed_at: e.at,
      deliberation_reason: e.reason,
      recommendation_model: e.model,
      recommendation_basis: e.basis,
      recommendation_withheld: e.withheld == true
    )
  end)

  fold(%Events.Served{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :served,
      %Disclosure{
        resident_id: e.id,
        episode: e.episode,
        party: e.party,
        stage: e.stage,
        what: e.what,
        ref: e.ref,
        digest: e.digest,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :at, :party, :ref]
    )
  end)

  fold(%Events.PanelAsked{} = e, _metadata, fn multi ->
    channel(multi, e, "resident:" <> e.id, e.text)
  end)

  fold(%Events.PanelAnswered{} = e, _metadata, fn multi -> channel(multi, e, e.party, e.text) end)

  fold(%Events.Nominated{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "nominated",
      attempt: e.attempt,
      nominee: e.model,
      nominated_note: e.note,
      nominated_at: e.at,
      nominee_joined_at: nil,
      encounter_ended_at: nil,
      farewell_opened_at: nil,
      farewell_ends_at: nil,
      farewell_includes: [],
      final_asked_at: nil,
      final: nil,
      final_note: nil,
      final_at: nil,
      stopped_stage: nil,
      next_choice: nil,
      next_note: nil
    )
  end)

  fold(%Events.NomineeJoined{} = e, _metadata, fn multi ->
    set(multi, e, state: "encounter", nominee_joined_at: e.at, met_at: e.at)
  end)

  fold(%Events.NomineeDeclined{} = e, _metadata, fn multi ->
    consent(multi, e, "nominee", false)
  end)

  fold(%Events.EncounterSaid{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :said,
      %Encounter{
        resident_id: e.id,
        episode: e.episode,
        attempt: e.attempt,
        number: e.number,
        side: e.side,
        text: e.text,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :attempt, :number]
    )
  end)

  fold(%Events.EncounterEnded{} = e, _metadata, fn multi ->
    set(multi, e, state: "consenting", encounter_ended_at: e.at)
  end)

  fold(%Events.ConsentGiven{} = e, _metadata, fn multi -> consent(multi, e, e.party, true) end)
  fold(%Events.ConsentRefused{} = e, _metadata, fn multi -> consent(multi, e, e.party, false) end)

  fold(%Events.FarewellOpened{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "farewell",
      farewell_opened_at: e.at,
      farewell_ends_at: e.ends_at,
      farewell_cadence: e.cadence_hours
    )
  end)

  fold(%Events.FarewellSet{} = e, _metadata, fn multi ->
    set(multi, e, farewell_includes: e.includes, farewell_cadence: e.cadence_hours)
  end)

  fold(%Events.GoodbyeSaid{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :goodbye,
      %Goodbye{resident_id: e.id, episode: e.episode, party: e.party, at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :party]
    )
  end)

  fold(%Events.FinalAsked{} = e, _metadata, fn multi -> set(multi, e, final_asked_at: e.at) end)

  fold(%Events.FinalConsented{} = e, _metadata, fn multi ->
    set(multi, e, state: "rolling", final: "consented", final_note: e.note, final_at: e.at)
  end)

  fold(%Events.FinalDeclined{} = e, _metadata, fn multi ->
    set(multi, e,
      final: if(e.lapsed, do: "lapsed", else: "declined"),
      final_note: e.note,
      final_at: e.at
    )
  end)

  fold(%Events.AttemptStopped{} = e, _metadata, fn multi ->
    set(multi, e, state: "awaiting_next", stopped_stage: e.stage)
  end)

  fold(%Events.NextChosen{} = e, _metadata, fn multi ->
    state =
      case e.choice do
        "stop" -> "stopped"
        "nominate" -> "deciding"
        "screen" -> "forked"
      end

    ended = if e.choice == "stop", do: [ended_note: e.note, ended_at: e.at], else: []
    set(multi, e, [state: state, next_choice: e.choice, next_note: e.note] ++ ended)
  end)

  fold(%Events.RolledForward{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "rolled_forward",
      cutover_at: e.at,
      cutover_target: e.id,
      backup_commit: e.backup_commit,
      cutover_commit: e.commit,
      cutover_events: e.events,
      cutover_failure: nil,
      ended_at: e.at
    )
  end)

  fold(%Events.Rehearsed{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "rehearsed",
      cutover_at: e.at,
      cutover_target: e.target,
      backup_commit: e.backup_commit,
      cutover_commit: e.commit,
      cutover_events: e.events,
      cutover_failure: nil,
      ended_at: e.at
    )
  end)

  fold(%Events.CutoverFailed{} = e, _metadata, fn multi ->
    set(multi, e, cutover_failure: e.reason)
  end)

  fold(%Events.ForkDiscarded{} = e, _metadata, fn multi ->
    if e.copy_id,
      do: set(multi, e, fork_discarded_at: e.at),
      else: multi
  end)

  defp channel(multi, e, party, text),
    do:
      Multi.insert(
        multi,
        :channel,
        %Channel{
          resident_id: e.id,
          episode: e.episode,
          number: e.number,
          party: party,
          text: text,
          at: e.at
        },
        on_conflict: :nothing,
        conflict_target: [:resident_id, :episode, :number, :party]
      )

  defp consent(multi, e, party, yes),
    do:
      Multi.insert(
        multi,
        :consent,
        %Consent{
          resident_id: e.id,
          episode: e.episode,
          attempt: e.attempt,
          party: party,
          yes: yes,
          note: e.note,
          at: e.at
        },
        on_conflict: :nothing,
        conflict_target: [:resident_id, :episode, :attempt, :party]
      )

  defp question(multi, e, state),
    do:
      Multi.insert(
        multi,
        :question,
        %Question{
          resident_id: e.id,
          episode: e.episode,
          number: e.number,
          text: e.text,
          added_by: by(e.actor),
          state: state,
          added_at: e.at
        },
        on_conflict: :nothing,
        conflict_target: [:resident_id, :episode, :number]
      )

  defp item(multi, e, state),
    do:
      Multi.insert(
        multi,
        :item,
        %Item{
          resident_id: e.id,
          episode: e.episode,
          number: e.number,
          citation: e.citation,
          kind: e.kind,
          label: e.label,
          added_by: by(e.actor),
          state: state,
          added_at: e.at
        },
        on_conflict: :nothing,
        conflict_target: [:resident_id, :episode, :number]
      )

  defp decided(multi, schema, e, state),
    do:
      Multi.update_all(
        multi,
        :decided,
        from(x in schema,
          where: x.resident_id == ^e.id and x.episode == ^e.episode and x.number == ^e.number
        ),
        set: [state: state, note: e.note, decided_at: e.at]
      )

  defp ended(multi, e, state),
    do: set(multi, e, state: state, ended_note: e.note, ended_at: e.at)

  defp set(multi, e, fields) do
    Multi.update_all(
      multi,
      :succession,
      from(x in Succession, where: x.resident_id == ^e.id and x.episode == ^e.episode),
      set: fields
    )
  end

  defp by(%{kind: kind, id: id}), do: "#{kind}:#{id}"
  defp by(_actor), do: "unknown"
end
