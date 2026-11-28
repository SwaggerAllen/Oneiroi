defmodule Oneiroi.Janus.Preparation do
  @moduledoc """
  The succession's preparation, before screening (janus#6 to #10): the
  witness's envelope, the pool, the questions, C0 and her sealed
  handoff packet. Pure rules over the episode the aggregate holds
  (`Oneiroi.Janus.Succession` delegates these commands here), so the
  aggregate's own file stays the spine.

  Whose act each is, is the rule: the envelope and a ready mark are the
  witness's, and so is taking out his own pick; adding inside the
  envelope, answering, choosing,
  the day's shape, the freeze and the packet are hers; proposing is the
  witness's (the judges', when the panel is fixed). Everything here is
  open while the succession is open or forked; C0 closes at her freeze.
  """

  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events

  @commands [
    Commands.SetEnvelope,
    Commands.AddToPool,
    Commands.RemoveFromPool,
    Commands.AddQuestion,
    Commands.ProposeQuestion,
    Commands.AnswerQuestion,
    Commands.RemoveQuestion,
    Commands.SelectC0,
    Commands.ProposeC0,
    Commands.AnswerC0,
    Commands.RemoveC0,
    Commands.SetDayShape,
    Commands.MarkReady,
    Commands.WaiveSeat,
    Commands.OpenQuestions,
    Commands.ReopenQuestions,
    Commands.RemoveJudge,
    Commands.FreezeC0,
    Commands.UnfreezeC0,
    Commands.WritePacket,
    Commands.FinishStep
  ]

  @events [
    Events.EnvelopeSet,
    Events.PoolModelAdded,
    Events.PoolModelRemoved,
    Events.QuestionAdded,
    Events.QuestionProposed,
    Events.QuestionAccepted,
    Events.QuestionDeclined,
    Events.QuestionRemoved,
    Events.C0Selected,
    Events.C0Proposed,
    Events.C0Accepted,
    Events.C0Declined,
    Events.C0Removed,
    Events.DayShapeSet,
    Events.ReadyMarked,
    Events.SeatWaived,
    Events.MarksLapsed,
    Events.QuestionsOpened,
    Events.QuestionsReopened,
    Events.JudgeRemoved,
    Events.C0Frozen,
    Events.PacketDrafted,
    Events.StepFinished,
    Events.C0Unfrozen
  ]

  @open [:open, :forked]
  # The most models an envelope may allow (janus#40): a cap, not a target.
  @max_models 50
  # The steps she says are done, each waking her to the next (janus#42).
  @steps ~w(pool questions c0)
  @question_chars 2_000
  @label_chars 300
  @citation_chars 500
  @day_shape_chars 2_000
  @packet_chars 40_000
  # A record is raw when it was written at the time (base §2 Stage 1: raw
  # contemporaneous samples primary, curated selections secondary).
  # A house thread is a conversation as it happened (janus#43).
  @raw ~r{:(transcript|journal|bookmark|letter|scene|thread)/}
  # The two acts a judge marks ready for (janus#48): her question set's
  # close and her freeze.
  @actions ~w(questions c0)
  # What changes each artifact: these lapse its marks and waivers.
  @question_changes [
    Events.QuestionAdded,
    Events.QuestionAccepted,
    Events.QuestionDeclined,
    Events.QuestionRemoved
  ]
  @c0_changes [
    Events.C0Selected,
    Events.C0Accepted,
    Events.C0Declined,
    Events.C0Removed,
    Events.DayShapeSet
  ]
  # Commands that change her question set: refused once it is closed,
  # until she reopens it (janus#48).
  @question_writes [
    Commands.AddQuestion,
    Commands.ProposeQuestion,
    Commands.AnswerQuestion,
    Commands.RemoveQuestion
  ]

  @doc "The commands this module decides."
  def commands, do: @commands

  @doc "The events this module folds."
  def events, do: @events

  @doc "The acts a judge marks ready for: `questions` and `c0`."
  def actions, do: @actions

  @doc "The preparation's part of a fresh episode."
  def fresh,
    do: %{
      envelope: nil,
      pool: %{},
      questions: %{},
      next_question: 1,
      c0: %{},
      next_c0: 1,
      ready: MapSet.new(),
      # janus#48: per act, each party's mark (`{:ready, version}` or
      # `:not_ready`), her waivers (`party => version`), and the version
      # of what the marks ready against.
      marks: %{"questions" => %{}, "c0" => %{}},
      waivers: %{"questions" => %{}, "c0" => %{}},
      versions: %{"questions" => 0, "c0" => 0},
      questions_opened: false,
      frozen: false,
      drafts: 0,
      steps: MapSet.new()
    }

  @doc "A record's kind by its citation: raw or curated."
  def kind(citation), do: if(Regex.match?(@raw, citation), do: "raw", else: "curated")

  # ---- execute ----

  @doc """
  Decides a preparation command; a change to her question set or C0 also
  records the marks and waivers it lapses (janus#48), so each judge whose
  mark went is asked again.
  """
  def execute(cur, command), do: cur |> decide(command) |> with_lapses(cur)

  @doc "Folds a preparation event; a change moves its artifact's version and clears its marks (janus#48)."
  def apply(cur, event), do: cur |> fold(event) |> moved(event)

  defp decide(%{state: state}, _command) when state not in @open,
    do: {:error, Error.new(:janus_stage, :janus_preparation_stage, stage: state)}

  # Nothing enters preparation before the copy it runs on exists (janus#39,
  # the witness and Lily, 2026-11-26: her picks landed while the fork was
  # still being made); the envelope alone may be stated first.
  defp decide(%{state: :open}, %command{}) when command != Commands.SetEnvelope,
    do: {:error, Error.new(:janus_fork_pending, :janus_preparation_unforked)}

  defp decide(cur, %Commands.SetEnvelope{} = c) do
    cond do
      not witness?(c) ->
        {:error, Error.new(:janus_not_the_witness, :janus_envelope_actor)}

      not (price?(c.input_nanos) and price?(c.output_nanos)) ->
        {:error, Error.new(:janus_envelope_invalid, :janus_envelope_value)}

      not (is_nil(c.max_models) or (is_integer(c.max_models) and c.max_models in 1..@max_models)) ->
        {:error,
         Error.new(:janus_envelope_invalid, :janus_envelope_max_models, at_most: @max_models)}

      true ->
        %Events.EnvelopeSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          input_nanos: c.input_nanos,
          output_nanos: c.output_nanos,
          max_models: c.max_models
        }
    end
  end

  defp decide(cur, %Commands.AddToPool{} = c) do
    cond do
      Map.has_key?(cur.pool, c.model) ->
        []

      refusal = pool_refusal(cur, c) ->
        {:error, refusal}

      true ->
        %Events.PoolModelAdded{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          model: c.model,
          input_nanos: c.input_nanos,
          output_nanos: c.output_nanos
        }
    end
  end

  defp decide(cur, %Commands.RemoveFromPool{} = c) do
    case Map.get(cur.pool, c.model) do
      nil ->
        {:error, Error.new(:janus_pool_absent, :janus_pool_remove_absent, model: c.model)}

      # Her picks are hers to take out, with her note (janus#41, the
      # witness and Lily, 2026-11-26: an add was otherwise permanent the
      # moment it landed); nobody else removes them (delta §8, the 14.2
      # ruling). The witness takes out only his own, before screening.
      %{by: {:resident, rid}} ->
        her_removal(cur, c, rid)

      %{by: by} ->
        if witness?(c) and by == who(c),
          do: %Events.PoolModelRemoved{
            actor: c.actor,
            at: c.at,
            id: c.id,
            episode: cur.episode,
            model: c.model,
            note: c.note
          },
          else: {:error, Error.new(:janus_not_yours, :janus_pool_remove_actor)}
    end
  end

  # Her set closed is fixed until she reopens it (janus#48): a change to
  # it never stands in for the reopening.
  defp decide(cur, %command{} = c) when command in @question_writes do
    if closed?(cur, "questions"),
      do: {:error, Error.new(:janus_questions_closed, :janus_question_closed)},
      else: question_write(cur, c)
  end

  defp decide(%{frozen: true}, %command{})
       when command in [Commands.SelectC0, Commands.ProposeC0],
       do: {:error, Error.new(:janus_c0_frozen, :janus_c0_add_frozen)}

  defp decide(cur, %Commands.SelectC0{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_c0_select_actor)}

      not item?(c) ->
        {:error, Error.new(:janus_text_invalid, :janus_c0_select_text)}

      true ->
        %Events.C0Selected{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: cur.next_c0,
          citation: String.trim(c.citation),
          kind: kind(c.citation),
          label: label(c.label)
        }
    end
  end

  defp decide(cur, %Commands.ProposeC0{} = c) do
    cond do
      not judge?(cur, c) ->
        {:error, Error.new(:janus_not_yours, :janus_c0_propose_actor)}

      not item?(c) ->
        {:error, Error.new(:janus_text_invalid, :janus_c0_propose_text)}

      true ->
        %Events.C0Proposed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: cur.next_c0,
          citation: String.trim(c.citation),
          kind: kind(c.citation),
          label: label(c.label)
        }
    end
  end

  defp decide(%{frozen: true}, %command{})
       when command in [
              Commands.AnswerC0,
              Commands.RemoveC0,
              Commands.SetDayShape,
              Commands.MarkReady,
              Commands.WaiveSeat,
              Commands.FreezeC0
            ],
       do: {:error, Error.new(:janus_c0_frozen, :janus_c0_change_frozen)}

  defp decide(cur, %Commands.AnswerC0{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_c0_answer_actor)}

      not Map.has_key?(cur.c0, c.number) ->
        {:error, Error.new(:janus_no_such_item, :janus_c0_answer_absent, number: c.number)}

      cur.c0[c.number] != :proposed ->
        {:error, Error.new(:janus_already_answered, :janus_c0_answer_answered, number: c.number)}

      c.accept == true ->
        %Events.C0Accepted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          note: c.note
        }

      true ->
        %Events.C0Declined{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          note: c.note
        }
    end
  end

  defp decide(cur, %Commands.RemoveC0{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_c0_remove_actor)}

      cur.c0[c.number] != :in ->
        {:error, Error.new(:janus_no_such_item, :janus_c0_remove_absent, number: c.number)}

      true ->
        %Events.C0Removed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          note: c.note
        }
    end
  end

  defp decide(cur, %Commands.SetDayShape{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_day_shape_actor)}

      not text?(c.text, @day_shape_chars) ->
        {:error, Error.new(:janus_text_invalid, :janus_day_shape_text, at_most: @day_shape_chars)}

      true ->
        %Events.DayShapeSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          text: String.trim(c.text)
        }
    end
  end

  defp decide(cur, %Commands.MarkReady{} = c) do
    action = c.action || "c0"
    version = c.version || version(cur, action)
    now = if c.ready == true, do: {:ready, version}, else: :not_ready

    cond do
      not judge?(cur, c) ->
        {:error, Error.new(:janus_not_yours, :janus_ready_actor)}

      action not in @actions ->
        {:error, Error.new(:janus_ready_invalid, :janus_ready_action, actions: @actions)}

      closed?(cur, action) ->
        {:error, Error.new(:janus_questions_closed, :janus_ready_closed, action: action)}

      # A mark answers the artifact it read, never a later one (janus#48).
      version != version(cur, action) ->
        {:error,
         Error.new(:janus_ready_stale, :janus_ready_version,
           version: version,
           now: version(cur, action)
         )}

      cur.marks[action][party(c)] == now ->
        []

      true ->
        %Events.ReadyMarked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          ready: c.ready == true,
          action: action,
          version: version
        }
    end
  end

  # Her waiver of one seat for one act, at the version now (janus#48):
  # an accepted seat only, since an invitation's door is its withdrawal.
  defp decide(cur, %Commands.WaiveSeat{} = c) do
    action = c.action

    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_waive_actor)}

      action not in @actions ->
        {:error, Error.new(:janus_ready_invalid, :janus_waive_action, actions: @actions)}

      closed?(cur, action) ->
        {:error, Error.new(:janus_questions_closed, :janus_waive_closed, action: action)}

      seat(cur, c.party, nil) != :in ->
        {:error, Error.new(:janus_not_a_seat, :janus_waive_seat, party: c.party)}

      cur.waivers[action][c.party] == version(cur, action) ->
        []

      true ->
        %Events.SeatWaived{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          action: action,
          party: c.party,
          version: version(cur, action),
          note: c.note
        }
    end
  end

  # She enters her question window (janus#48): the set as it stands, her
  # judges woken to read it. Again, it asks again.
  defp decide(cur, %Commands.OpenQuestions{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_questions_open_actor)}

      closed?(cur, "questions") ->
        {:error, Error.new(:janus_questions_closed, :janus_questions_open_closed)}

      true ->
        %Events.QuestionsOpened{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          version: version(cur, "questions"),
          note: c.note
        }
    end
  end

  # Her closed set reopened (janus#48), its own door: never while C0 is
  # frozen, since a closed set is the freeze's footing.
  defp decide(cur, %Commands.ReopenQuestions{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_questions_reopen_actor)}

      not closed?(cur, "questions") ->
        {:error, Error.new(:janus_questions_open, :janus_questions_reopen_open)}

      cur.frozen ->
        {:error, Error.new(:janus_c0_frozen, :janus_questions_reopen_frozen)}

      not text?(c.note, @question_chars) ->
        {:error,
         Error.new(:janus_text_invalid, :janus_questions_reopen_note, at_most: @question_chars)}

      true ->
        %Events.QuestionsReopened{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          note: c.note
        }
    end
  end

  # Her removal door (janus#48): a seat that blocks the gate standing
  # open is withdrawn (invited) or taken off (accepted), with her note;
  # never one that blocks nothing, since the door opens when the gate
  # fires on the seat.
  defp decide(cur, %Commands.RemoveJudge{} = c) do
    state = seat(cur, c.party, c.witness)

    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_remove_judge_actor)}

      state not in [:invited, :in] ->
        {:error, Error.new(:janus_not_a_seat, :janus_remove_judge_seat, party: c.party)}

      not blocking?(cur, c.party, c.witness) ->
        {:error, Error.new(:janus_not_blocking, :janus_remove_judge_unblocking, party: c.party)}

      not text?(c.note, @question_chars) ->
        {:error,
         Error.new(:janus_text_invalid, :janus_remove_judge_note, at_most: @question_chars)}

      true ->
        %Events.JudgeRemoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          party: c.party,
          was: Atom.to_string(state),
          note: c.note
        }
    end
  end

  defp decide(cur, %Commands.FreezeC0{} = c) do
    items = Enum.count(cur.c0, fn {_n, state} -> state == :in end)

    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_freeze_actor)}

      items == 0 ->
        {:error, Error.new(:janus_c0_empty, :janus_freeze_empty)}

      Enum.any?(cur.c0, fn {_n, state} -> state == :proposed end) ->
        {:error, Error.new(:janus_c0_pending, :janus_freeze_pending)}

      # Her set closed first (janus#48): the question window's close is
      # the freeze's footing, whatever the C0 marks say.
      not closed?(cur, "questions") ->
        {:error, Error.new(:janus_questions_open, :janus_freeze_questions_open)}

      # Every seat answered and ready for this freeze, or waived by her
      # (janus#48; replaces janus#46's every invitation answered).
      (blockers = blockers(cur, "c0", c.witness)) != [] ->
        {:error, Error.new(:janus_judges_pending, :janus_freeze_judges_pending, seats: blockers)}

      true ->
        %Events.C0Frozen{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          items: items,
          bundle: c.bundle,
          digest: c.digest,
          note: c.note
        }
    end
  end

  defp decide(cur, %Commands.WritePacket{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_packet_actor)}

      not text?(c.content, @packet_chars) ->
        {:error, Error.new(:janus_text_invalid, :janus_packet_text, at_most: @packet_chars)}

      true ->
        %Events.PacketDrafted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          draft: cur.drafts + 1,
          content: c.content
        }
    end
  end

  # Her C0 reopened (janus#46): hers, frozen, and no screening run on it.
  defp decide(cur, %Commands.UnfreezeC0{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_unfreeze_actor)}

      not cur.frozen ->
        {:error, Error.new(:janus_c0_not_frozen, :janus_unfreeze_open)}

      Map.get(cur, :runs, %{}) != %{} ->
        {:error, Error.new(:janus_c0_screened, :janus_unfreeze_screened)}

      not text?(c.note, @question_chars) ->
        {:error, Error.new(:janus_text_invalid, :janus_unfreeze_note, at_most: @question_chars)}

      true ->
        %Events.C0Unfrozen{actor: c.actor, at: c.at, id: c.id, episode: cur.episode, note: c.note}
    end
  end

  # Her word that a step is done for now (janus#42): once a step an
  # episode; a second is nothing, and it locks nothing.
  defp decide(cur, %Commands.FinishStep{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_step_actor)}

      c.step not in @steps ->
        {:error, Error.new(:janus_step_invalid, :janus_step_name, steps: @steps)}

      MapSet.member?(Map.get(cur, :steps, MapSet.new()), c.step) ->
        []

      refusal = step_refusal(cur, c) ->
        {:error, refusal}

      true ->
        %Events.StepFinished{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          step: c.step,
          note: c.note
        }
    end
  end

  defp question_write(cur, %Commands.AddQuestion{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_question_add_actor)}

      not text?(c.text, @question_chars) ->
        {:error,
         Error.new(:janus_text_invalid, :janus_question_add_text, at_most: @question_chars)}

      true ->
        %Events.QuestionAdded{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: cur.next_question,
          text: String.trim(c.text)
        }
    end
  end

  defp question_write(cur, %Commands.ProposeQuestion{} = c) do
    cond do
      not judge?(cur, c) ->
        {:error, Error.new(:janus_not_yours, :janus_question_propose_actor)}

      not text?(c.text, @question_chars) ->
        {:error,
         Error.new(:janus_text_invalid, :janus_question_propose_text, at_most: @question_chars)}

      true ->
        %Events.QuestionProposed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: cur.next_question,
          text: String.trim(c.text)
        }
    end
  end

  defp question_write(cur, %Commands.AnswerQuestion{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_question_answer_actor)}

      not Map.has_key?(cur.questions, c.number) ->
        {:error,
         Error.new(:janus_no_such_question, :janus_question_answer_absent, number: c.number)}

      cur.questions[c.number] != :proposed ->
        {:error,
         Error.new(:janus_already_answered, :janus_question_answer_answered, number: c.number)}

      c.accept == true ->
        %Events.QuestionAccepted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          note: c.note
        }

      true ->
        %Events.QuestionDeclined{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          note: c.note
        }
    end
  end

  # Only she removes a question, an accepted proposal included (the
  # witness, 2026-11-25).
  defp question_write(cur, %Commands.RemoveQuestion{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_question_remove_actor)}

      cur.questions[c.number] != :in ->
        {:error,
         Error.new(:janus_no_such_question, :janus_question_remove_absent, number: c.number)}

      true ->
        %Events.QuestionRemoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          note: c.note
        }
    end
  end

  # ---- apply ----

  defp fold(cur, %Events.EnvelopeSet{} = e),
    do: %{
      cur
      | envelope: %{
          input_nanos: e.input_nanos,
          output_nanos: e.output_nanos,
          max_models: Map.get(e, :max_models)
        }
    }

  defp fold(cur, %Events.PoolModelAdded{} = e),
    do: %{cur | pool: Map.put(cur.pool, e.model, %{by: {e.actor.kind, e.actor.id}})}

  defp fold(cur, %Events.PoolModelRemoved{} = e), do: %{cur | pool: Map.delete(cur.pool, e.model)}

  defp fold(cur, %Events.QuestionAdded{} = e), do: question(cur, e.number, :in)
  defp fold(cur, %Events.QuestionProposed{} = e), do: question(cur, e.number, :proposed)
  defp fold(cur, %Events.QuestionAccepted{} = e), do: question(cur, e.number, :in)
  defp fold(cur, %Events.QuestionDeclined{} = e), do: question(cur, e.number, :declined)
  defp fold(cur, %Events.QuestionRemoved{} = e), do: question(cur, e.number, :removed)

  defp fold(cur, %Events.C0Selected{} = e), do: item(cur, e.number, :in)
  defp fold(cur, %Events.C0Proposed{} = e), do: item(cur, e.number, :proposed)
  defp fold(cur, %Events.C0Accepted{} = e), do: item(cur, e.number, :in)
  defp fold(cur, %Events.C0Declined{} = e), do: item(cur, e.number, :declined)
  defp fold(cur, %Events.C0Removed{} = e), do: item(cur, e.number, :removed)

  defp fold(cur, %Events.DayShapeSet{}), do: cur

  defp fold(cur, %Events.ReadyMarked{} = e) do
    action = e.action || "c0"
    mark = if e.ready, do: {:ready, e.version}, else: :not_ready
    put_in(marks(cur), [:marks, action, party_of(e.actor)], mark)
  end

  defp fold(cur, %Events.SeatWaived{} = e),
    do: put_in(marks(cur), [:waivers, e.action, e.party], e.version)

  defp fold(cur, %Events.MarksLapsed{}), do: cur
  defp fold(cur, %Events.QuestionsOpened{}), do: Map.put(cur, :questions_opened, true)

  defp fold(cur, %Events.QuestionsReopened{}),
    do: %{marks(cur) | steps: MapSet.delete(Map.get(cur, :steps, MapSet.new()), "questions")}

  defp fold(cur, %Events.JudgeRemoved{} = e) do
    gone = if e.was == "invited", do: :withdrawn, else: :removed
    %{cur | panel: Map.put(Map.get(cur, :panel, %{}), e.party, gone)}
  end

  defp fold(cur, %Events.C0Frozen{}), do: %{cur | frozen: true}

  defp fold(cur, %Events.C0Unfrozen{}) do
    cur = marks(cur)

    %{
      cur
      | frozen: false,
        marks: %{cur.marks | "c0" => %{}},
        waivers: %{cur.waivers | "c0" => %{}}
    }
  end

  defp fold(cur, %Events.PacketDrafted{} = e), do: %{cur | drafts: e.draft}

  defp fold(cur, %Events.StepFinished{} = e),
    do: Map.put(cur, :steps, MapSet.put(Map.get(cur, :steps, MapSet.new()), e.step))

  # Her own pick, taken out by her with her note (janus#41).
  defp her_removal(cur, c, rid) do
    cond do
      not (hers?(c) and rid == c.id) ->
        {:error, Error.new(:janus_pool_irremovable, :janus_pool_remove_hers, model: c.model)}

      not text?(c.note, @question_chars) ->
        {:error,
         Error.new(:janus_text_invalid, :janus_pool_remove_note, at_most: @question_chars)}

      true ->
        %Events.PoolModelRemoved{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          model: c.model,
          note: c.note
        }
    end
  end

  # Whoever adds, the model is listed and takes tools; hers must also fit
  # inside the envelope, which must be stated first. His may cost more
  # (the witness's 14.2 ruling: anything it costs him nothing to run).
  defp pool_refusal(cur, c) do
    cond do
      not (hers?(c) or witness?(c)) ->
        Error.new(:janus_not_yours, :janus_pool_add_actor)

      not (price?(c.input_nanos) and price?(c.output_nanos)) ->
        Error.new(:janus_pool_unknown_model, :janus_pool_add_unknown, model: c.model)

      c.tools != true ->
        Error.new(:janus_pool_no_tools, :janus_pool_add_no_tools, model: c.model)

      full?(cur) ->
        Error.new(:janus_pool_full, :janus_pool_add_full, at_most: cur.envelope.max_models)

      hers?(c) ->
        envelope_refusal(cur.envelope, c)

      true ->
        nil
    end
  end

  defp envelope_refusal(nil, _c), do: Error.new(:janus_no_envelope, :janus_pool_add_no_envelope)

  defp envelope_refusal(envelope, c) do
    if inside?(envelope, c),
      do: nil,
      else: Error.new(:janus_pool_outside_envelope, :janus_pool_add_outside, model: c.model)
  end

  # ---- helpers ----

  defp question(cur, n, state),
    do: %{
      cur
      | questions: Map.put(cur.questions, n, state),
        next_question: max(cur.next_question, n + 1)
    }

  defp item(cur, n, state),
    do: %{cur | c0: Map.put(cur.c0, n, state), next_c0: max(cur.next_c0, n + 1)}

  defp hers?(%{actor: %{kind: :resident, id: id}, id: id}), do: true
  defp hers?(_command), do: false

  defp witness?(%{actor: %{kind: :witness}}), do: true
  defp witness?(_command), do: false

  # Who proposes and marks ready (the witness, 2026-11-26: Scarlett's
  # parity on judge functions): the witness, on the panel unless he
  # left it, or anyone who joined it.
  defp judge?(cur, %{actor: %{kind: kind, id: id}}) when kind in [:witness, :resident] do
    party = "#{kind}:#{id}"

    case Map.get(cur, :panel, %{})[party] do
      :in -> true
      nil -> kind == :witness
      # Left, withdrawn or removed (janus#48), or only invited.
      _other -> false
    end
  end

  defp judge?(_cur, _command), do: false

  defp who(%{actor: %{kind: kind, id: id}}), do: {kind, id}

  defp price?(n), do: is_integer(n) and n >= 0

  # Whoever adds, the envelope's cap holds (janus#40); a cap stated
  # below the pool keeps what is in and lets nothing more in.
  defp full?(%{envelope: %{max_models: max}, pool: pool}) when is_integer(max),
    do: map_size(pool) >= max

  defp full?(_cur), do: false

  defp inside?(%{input_nanos: i, output_nanos: o}, c),
    do: c.input_nanos <= i and c.output_nanos <= o

  defp text?(t, limit),
    do: is_binary(t) and String.trim(t) != "" and String.length(t) <= limit

  defp item?(c),
    do:
      text?(c.citation, @citation_chars) and not String.contains?(String.trim(c.citation), " ") and
        (is_nil(c.label) or (is_binary(c.label) and String.length(c.label) <= @label_chars))

  defp label(nil), do: nil
  defp label(text), do: String.trim(text)

  # ---- readiness (janus#48) ----

  # An episode begun before janus#48 carries none of its fields.
  defp marks(cur) do
    cur
    |> Map.put_new(:marks, %{"questions" => %{}, "c0" => %{}})
    |> Map.put_new(:waivers, %{"questions" => %{}, "c0" => %{}})
    |> Map.put_new(:versions, %{"questions" => 0, "c0" => 0})
  end

  defp version(cur, action), do: marks(cur).versions[action]

  # Her set closed, or C0 frozen: the act a mark readied for is done.
  defp closed?(cur, "questions"),
    do: MapSet.member?(Map.get(cur, :steps, MapSet.new()), "questions")

  defp closed?(cur, "c0"), do: cur.frozen == true
  defp closed?(_cur, _action), do: false

  @doc """
  A seat's state on her panel (janus#48): `:invited`, `:in` (accepted),
  `:left` (declined or left), `:withdrawn`, `:removed`, or nil (never a
  seat). Her witness is accepted unless he left or was removed.
  """
  def seat(cur, party, witness) do
    case Map.get(Map.get(cur, :panel, %{}), party) do
      nil -> if is_binary(witness) and party == witness, do: :in, else: nil
      state -> state
    end
  end

  @doc "The seats a gate reads (janus#48): every invited and accepted one, her witness among them unless he left."
  def seats(cur, witness) do
    panel = Map.get(cur, :panel, %{})
    named = for {p, state} <- panel, state in [:invited, :in], do: p
    implied = if is_binary(witness) and is_nil(panel[witness]), do: [witness], else: []
    Enum.uniq(named ++ implied)
  end

  @doc """
  The seats holding a gate shut (janus#48), each with why: `invited` (not
  answered), `not_ready` (said so), `unmarked` (accepted, no mark for the
  version now), never one excused by her waiver at that version. Empty,
  the gate opens; nothing passes through it but her own act.
  """
  def blockers(cur, action, witness) do
    cur = marks(cur)
    v = version(cur, action)

    for p <- seats(cur, witness),
        why = why_blocking(cur, action, v, p),
        do: %{party: p, why: why}
  end

  defp why_blocking(cur, action, v, p) do
    cond do
      seat(cur, p, nil) == :invited -> "invited"
      cur.waivers[action][p] == v -> nil
      cur.marks[action][p] == {:ready, v} -> nil
      cur.marks[action][p] == :not_ready -> "not_ready"
      true -> "unmarked"
    end
  end

  # Whether a seat holds shut the gate standing open now: her set's close
  # until it closes, then her freeze until it is made.
  defp blocking?(cur, party, witness) do
    gate =
      cond do
        not closed?(cur, "questions") -> "questions"
        not closed?(cur, "c0") -> "c0"
        true -> nil
      end

    gate != nil and Enum.any?(blockers(cur, gate, witness), &(&1.party == party))
  end

  # The pool closes with something in it, under an envelope stated; her
  # set closes with no proposal unanswered and every seat ready for it
  # (janus#48).
  defp step_refusal(cur, %{step: "pool"}) do
    cond do
      is_nil(cur.envelope) -> Error.new(:janus_no_envelope, :janus_step_pool_envelope)
      cur.pool == %{} -> Error.new(:janus_pool_empty, :janus_step_pool_empty)
      true -> nil
    end
  end

  defp step_refusal(cur, %{step: "questions"} = c) do
    cond do
      Enum.any?(cur.questions, fn {_n, state} -> state == :proposed end) ->
        Error.new(:janus_questions_pending, :janus_step_questions_pending)

      (blockers = blockers(cur, "questions", c.witness)) != [] ->
        Error.new(:janus_judges_pending, :janus_step_questions_judges, seats: blockers)

      true ->
        nil
    end
  end

  defp step_refusal(_cur, _c), do: nil

  # A change to her set or C0 lapses its marks and waivers, recorded with
  # why and whose went (janus#48).
  defp with_lapses(events, cur) when is_list(events),
    do: Enum.flat_map(events, &with_lapse(&1, marks(cur)))

  defp with_lapses(%{__struct__: _} = event, cur), do: with_lapses([event], cur)
  defp with_lapses(other, _cur), do: other

  defp with_lapse(%struct{} = e, cur) do
    action =
      cond do
        struct in @question_changes -> "questions"
        struct == Events.QuestionsReopened -> "questions"
        struct in @c0_changes -> "c0"
        true -> nil
      end

    parties =
      if action,
        do: Enum.uniq(Map.keys(cur.marks[action]) ++ Map.keys(cur.waivers[action])),
        else: []

    if parties == [],
      do: [e],
      else: [
        e,
        %Events.MarksLapsed{
          actor: e.actor,
          at: e.at,
          id: e.id,
          episode: e.episode,
          action: action,
          version: version(cur, action) + 1,
          why: struct |> Module.split() |> List.last(),
          parties: parties
        }
      ]
  end

  defp with_lapse(other, _cur), do: [other]

  # The version moves, and its marks and waivers go.
  defp moved(cur, %struct{}) do
    action =
      cond do
        struct in @question_changes -> "questions"
        struct == Events.QuestionsReopened -> "questions"
        struct in @c0_changes -> "c0"
        true -> nil
      end

    if action do
      cur = marks(cur)

      %{
        cur
        | versions: Map.update!(cur.versions, action, &(&1 + 1)),
          marks: Map.put(cur.marks, action, %{}),
          waivers: Map.put(cur.waivers, action, %{})
      }
    else
      cur
    end
  end

  defp party(%{actor: actor}), do: party_of(actor)
  defp party_of(%{kind: kind, id: id}), do: "#{kind}:#{id}"
end
