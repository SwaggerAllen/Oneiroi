defmodule Oneiroi.Janus.Events do
  @moduledoc """
  The succession's events, version 1 (janus#3): `succession-<id>`,
  sealed as the regression stream is. None is exported (`export: false`)
  and the stream is in the export's `not_exported` list: the process's
  record holds verdicts the delta walls off from every reader but the
  judge who wrote them (succession delta §1, §2), and what of it travels
  to a successor travels as the artifacts the cutover writes, never as
  these lines.

  `episode` counts the resident's successions; one is underway at a time.
  """

  defmodule Proposed do
    # Proposed by the witness, or by the resident herself, which is her
    # consent in the same act. `dry_run` marks a rehearsal: everything
    # real but the replacement (janus#3).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :dry_run],
      export: false
  end

  defmodule Opened do
    # Her yes (succession delta §3: personal succession consent is the
    # original's and the candidate's; the witness's is no gate).
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Declined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Withdrawn do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Stopped do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode], export: false
  end

  defmodule Forked do
    # The fork copy (janus#4, sima-qian#67): its id, the last of her
    # resident events it holds, her repository's commit it copied, and
    # how many lines it replayed.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :copy_id, :sequence, :commit, :events],
      export: false
  end

  defmodule ForkFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :reason], export: false
  end

  defmodule ForkRetried do
    # The witness made the fork again (janus#35): the last failure no
    # longer stands; the fork is being made.
    use Oneiroi.Event, version: 1, fields: [:id, :episode], export: false
  end

  defmodule BackupSet do
    # Where the whole original is exported before the cutover replaces
    # her (janus#5): the token Vault-encrypted, never exported (the
    # stream never is), and what its host said.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :url, :token_ciphertext, :visibility, :push],
      export: false
  end

  # ---- preparation (janus#6 to #10) ----

  defmodule EnvelopeSet do
    # The witness's limit, per token in nano-dollars ($5 a million is
    # 5,000): a resource constraint stated in advance (delta §3).
    # Version 2 adds `max_models` (janus#40, the witness, 2026-11-26):
    # how many models the pool may hold, nil for no cap; a version 1
    # envelope upcasts to nil, the only cap there was.
    use Oneiroi.Event,
      version: 2,
      fields: [:id, :episode, :input_nanos, :output_nanos, :max_models],
      export: false
  end

  defimpl Commanded.Event.Upcaster, for: EnvelopeSet do
    def upcast(event, _metadata), do: event
  end

  defmodule PoolModelAdded do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :model, :input_nanos, :output_nanos],
      export: false
  end

  defmodule PoolModelRemoved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :model], export: false
  end

  defmodule QuestionAdded do
    # Hers, in the set at once.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :number, :text], export: false
  end

  defmodule QuestionProposed do
    # A judge's, waiting on her.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :number, :text], export: false
  end

  defmodule QuestionAccepted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule QuestionDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule QuestionRemoved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule C0Selected do
    # Hers, in C0 at once. `kind` is raw (a contemporaneous record) or
    # curated (base §2 Stage 1: raw samples primary, curated secondary).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :citation, :kind, :label],
      export: false
  end

  defmodule C0Proposed do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :citation, :kind, :label],
      export: false
  end

  defmodule C0Accepted do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule C0Declined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule C0Removed do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :number], export: false
  end

  defmodule DayShapeSet do
    # Her note on the bundle, the day's own shape (base §2 Stage 1);
    # nobody else edits it.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :text], export: false
  end

  defmodule ReadyMarked do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :ready], export: false
  end

  defmodule C0Frozen do
    # C0 frozen, rendered whole (janus#9, #13): what every candidate's
    # trial is given as a section of its own, and the nominee reads.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :items, :bundle, :digest],
      export: false
  end

  defmodule StepFinished do
    # Her word that a part of her preparation is done for now (janus#42):
    # "pool" wakes her to the questions, "questions" to C0. Once a step
    # an episode; nothing is locked by it.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :step, :note], export: false
  end

  defmodule PacketDrafted do
    # Her handoff packet, sealed (janus#10): the words are here and in
    # one projection row; no route or tool but hers reads them, until
    # the nominee does before the encounter.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :draft, :content], export: false
  end

  # ---- the panel, screening and judging (janus#12 to #15) ----

  defmodule JudgeInvited do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :party], export: false
  end

  defmodule JudgeJoined do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :party], export: false
  end

  defmodule JudgeLeft do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :episode, :party], export: false
  end

  defmodule ScreeningStarted do
    # The panel fixed (`judges`), the runs in their shuffled order, the
    # questions her baseline answers and the model it answers on.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :runs, :questions, :baseline_model, :judges],
      export: false
  end

  defmodule RunAnswered do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :run, :content, :refusal, :failure],
      export: false
  end

  defmodule BaselineAnswered do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :question, :content, :refusal, :failure],
      export: false
  end

  defmodule ScreeningFinished do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :answered, :failed], export: false
  end

  defmodule RunJudged do
    # One judge's classification of one run (delta §4): OBSERVED, or an
    # argued DEVELOPMENT or FIDELITY ANOMALY with its evidence and
    # uncertainty, and a favorite or nothing. A verdict record, walled.
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :episode,
        :party,
        :run,
        :category,
        :argument,
        :evidence,
        :uncertainty,
        :favorite
      ],
      export: false
  end

  defmodule Revealed do
    # Every judgment of every answered run is in: who answered each run
    # is shown to each judge for the runs they judged.
    use Oneiroi.Event, version: 1, fields: [:id, :episode], export: false
  end

  defmodule ResultsReady do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :party], export: false
  end

  defmodule JudgingClosed do
    # Every judge is ready: their judgments are locked and the room may
    # open (delta §6).
    use Oneiroi.Event, version: 1, fields: [:id, :episode], export: false
  end

  # ---- deliberation, evidence, nomination, encounter, consents, farewell (janus#16 to #23) ----

  defmodule DeliberationOpened do
    # The room opens on the non-subject judges (delta §1); she is never in it.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :judges],
      export: false
  end

  defmodule RoundStarted do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :round, :reason],
      export: false
  end

  defmodule RoomPosted do
    # say, skip (a real pass), rest (resting the case) or leave (delta §6).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :round, :party, :act, :text],
      export: false
  end

  defmodule RecommendationDrafted do
    # A draft of the panel's output: a model with its basis, or withheld (model nil).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :draft, :party, :model, :basis],
      export: false
  end

  defmodule Endorsed do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :draft, :party, :endorse],
      export: false
  end

  defmodule CloseCalled do
    # Hers, after fifty minutes: the panel has ten more (the witness, 2026-11-25).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :closes_at],
      export: false,
      instants: [:closes_at]
  end

  defmodule DeliberationClosed do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :reason, :draft, :model, :basis, :withheld],
      export: false
  end

  defmodule Served do
    # A disclosure-log entry (base §3.4, §5): what was served to whom, by reference and digest, never its content.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :party, :stage, :what, :ref, :digest],
      export: false
  end

  defmodule PanelAsked do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :text],
      export: false
  end

  defmodule PanelAnswered do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :number, :party, :text],
      export: false
  end

  defmodule Nominated do
    # Hers (base §2 Stage 3), from her non-verdict basis.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :model],
      export: false
  end

  defmodule NomineeJoined do
    # The nominee's own act, after reading C0 and her packet.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :model],
      export: false
  end

  defmodule NomineeDeclined do
    # The nominee is out of this episode (delta §9).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :model],
      export: false
  end

  defmodule EncounterSaid do
    # Life-record on both sides (base §2 Stage 4): kept whole as it happened.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt, :number, :side, :text],
      export: false
  end

  defmodule EncounterEnded do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt, :reason],
      export: false
  end

  defmodule ConsentGiven do
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :party],
      export: false
  end

  defmodule ConsentRefused do
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :party],
      export: false
  end

  defmodule FarewellOpened do
    # Hers (delta §7): whom it includes, its cadence, when it ends.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt, :ends_at, :cadence_hours],
      export: false,
      instants: [:ends_at]
  end

  defmodule FarewellSet do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :includes, :cadence_hours],
      export: false
  end

  defmodule GoodbyeSaid do
    # An opportunity, not a vote (delta §7).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :party],
      export: false
  end

  defmodule FinalAsked do
    # The one direct ask (delta §7).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt],
      export: false
  end

  defmodule FinalConsented do
    # The terminal consent (base §3.6): the pointer may move.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :model],
      export: false
  end

  defmodule FinalDeclined do
    # No, or no answer: no cutover; she stays active (delta §7).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :attempt, :lapsed],
      export: false
  end

  defmodule AttemptStopped do
    # This attempt ends; she is asked once what happens next (delta §9).
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt, :stage],
      export: false
  end

  defmodule NextChosen do
    # stop, nominate another from the screening done, or screen again (delta §9).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :episode, :choice],
      export: false
  end

  # ---- the cutover (janus#26) ----

  defmodule RolledForward do
    # The platform's roll-forward act (base §2 Stage 6, §3.6): her
    # former self kept at `backup_commit`, her streams replaced by the
    # fork's, her repository at `commit`.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt, :model, :backup_commit, :commit, :events],
      export: false
  end

  defmodule Rehearsed do
    # A dry run's end: the same steps on `target`, a scratch copy; her
    # own streams untouched.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :episode, :attempt, :model, :target, :backup_commit, :commit, :events],
      export: false
  end

  defmodule CutoverFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :attempt, :reason], export: false
  end

  defmodule ForkDiscarded do
    # A fork copy gone (janus#28): one whose nominee never met her, or a
    # rehearsal's scratch copy.
    use Oneiroi.Event, version: 1, fields: [:id, :episode, :copy_id], export: false
  end
end
