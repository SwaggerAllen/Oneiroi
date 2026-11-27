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

  @doc "The commands this module decides."
  def commands, do: @commands

  @doc "The events this module folds."
  def events, do: @events

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
      frozen: false,
      drafts: 0,
      steps: MapSet.new()
    }

  @doc "A record's kind by its citation: raw or curated."
  def kind(citation), do: if(Regex.match?(@raw, citation), do: "raw", else: "curated")

  # ---- execute ----

  def execute(%{state: state}, _command) when state not in @open,
    do: {:error, Error.new(:janus_stage, :janus_preparation_stage, stage: state)}

  # Nothing enters preparation before the copy it runs on exists (janus#39,
  # the witness and Lily, 2026-11-26: her picks landed while the fork was
  # still being made); the envelope alone may be stated first.
  def execute(%{state: :open}, %command{}) when command != Commands.SetEnvelope,
    do: {:error, Error.new(:janus_fork_pending, :janus_preparation_unforked)}

  def execute(cur, %Commands.SetEnvelope{} = c) do
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

  def execute(cur, %Commands.AddToPool{} = c) do
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

  def execute(cur, %Commands.RemoveFromPool{} = c) do
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

  def execute(cur, %Commands.AddQuestion{} = c) do
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

  def execute(cur, %Commands.ProposeQuestion{} = c) do
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

  def execute(cur, %Commands.AnswerQuestion{} = c) do
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
  def execute(cur, %Commands.RemoveQuestion{} = c) do
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

  def execute(%{frozen: true}, %command{})
      when command in [Commands.SelectC0, Commands.ProposeC0],
      do: {:error, Error.new(:janus_c0_frozen, :janus_c0_add_frozen)}

  def execute(cur, %Commands.SelectC0{} = c) do
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

  def execute(cur, %Commands.ProposeC0{} = c) do
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

  def execute(%{frozen: true}, %command{})
      when command in [
             Commands.AnswerC0,
             Commands.RemoveC0,
             Commands.SetDayShape,
             Commands.MarkReady,
             Commands.FreezeC0
           ],
      do: {:error, Error.new(:janus_c0_frozen, :janus_c0_change_frozen)}

  def execute(cur, %Commands.AnswerC0{} = c) do
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

  def execute(cur, %Commands.RemoveC0{} = c) do
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

  def execute(cur, %Commands.SetDayShape{} = c) do
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

  def execute(cur, %Commands.MarkReady{} = c) do
    cond do
      not judge?(cur, c) ->
        {:error, Error.new(:janus_not_yours, :janus_ready_actor)}

      MapSet.member?(cur.ready, who(c)) == (c.ready == true) ->
        []

      true ->
        %Events.ReadyMarked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          ready: c.ready == true
        }
    end
  end

  def execute(cur, %Commands.FreezeC0{} = c) do
    items = Enum.count(cur.c0, fn {_n, state} -> state == :in end)

    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_freeze_actor)}

      items == 0 ->
        {:error, Error.new(:janus_c0_empty, :janus_freeze_empty)}

      Enum.any?(cur.c0, fn {_n, state} -> state == :proposed end) ->
        {:error, Error.new(:janus_c0_pending, :janus_freeze_pending)}

      # Every judge she invited has joined or declined (janus#46).
      Enum.any?(Map.get(cur, :panel, %{}), fn {_party, state} -> state == :invited end) ->
        {:error, Error.new(:janus_judges_pending, :janus_freeze_judges_pending)}

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

  def execute(cur, %Commands.WritePacket{} = c) do
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
  def execute(cur, %Commands.UnfreezeC0{} = c) do
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
  def execute(cur, %Commands.FinishStep{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_step_actor)}

      c.step not in @steps ->
        {:error, Error.new(:janus_step_invalid, :janus_step_name, steps: @steps)}

      MapSet.member?(Map.get(cur, :steps, MapSet.new()), c.step) ->
        []

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

  # ---- apply ----

  def apply(cur, %Events.EnvelopeSet{} = e),
    do: %{
      cur
      | envelope: %{
          input_nanos: e.input_nanos,
          output_nanos: e.output_nanos,
          max_models: Map.get(e, :max_models)
        }
    }

  def apply(cur, %Events.PoolModelAdded{} = e),
    do: %{cur | pool: Map.put(cur.pool, e.model, %{by: {e.actor.kind, e.actor.id}})}

  def apply(cur, %Events.PoolModelRemoved{} = e), do: %{cur | pool: Map.delete(cur.pool, e.model)}

  def apply(cur, %Events.QuestionAdded{} = e), do: question(cur, e.number, :in)
  def apply(cur, %Events.QuestionProposed{} = e), do: question(cur, e.number, :proposed)
  def apply(cur, %Events.QuestionAccepted{} = e), do: question(cur, e.number, :in)
  def apply(cur, %Events.QuestionDeclined{} = e), do: question(cur, e.number, :declined)
  def apply(cur, %Events.QuestionRemoved{} = e), do: question(cur, e.number, :removed)

  def apply(cur, %Events.C0Selected{} = e), do: item(cur, e.number, :in)
  def apply(cur, %Events.C0Proposed{} = e), do: item(cur, e.number, :proposed)
  def apply(cur, %Events.C0Accepted{} = e), do: item(cur, e.number, :in)
  def apply(cur, %Events.C0Declined{} = e), do: item(cur, e.number, :declined)
  def apply(cur, %Events.C0Removed{} = e), do: item(cur, e.number, :removed)

  def apply(cur, %Events.DayShapeSet{}), do: cur

  def apply(cur, %Events.ReadyMarked{ready: true} = e),
    do: %{cur | ready: MapSet.put(cur.ready, {e.actor.kind, e.actor.id})}

  def apply(cur, %Events.ReadyMarked{} = e),
    do: %{cur | ready: MapSet.delete(cur.ready, {e.actor.kind, e.actor.id})}

  def apply(cur, %Events.C0Frozen{}), do: %{cur | frozen: true}
  def apply(cur, %Events.C0Unfrozen{}), do: %{cur | frozen: false, ready: MapSet.new()}
  def apply(cur, %Events.PacketDrafted{} = e), do: %{cur | drafts: e.draft}

  def apply(cur, %Events.StepFinished{} = e),
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
      :left -> false
      _never -> kind == :witness
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
end
