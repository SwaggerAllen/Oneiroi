defmodule Oneiroi.Janus.Decision do
  @moduledoc """
  From the closed judging to the final gate (janus#16 to #21): the
  deliberation room, the evidence channel and her questions, the
  nomination, the nominee's reading and opt-in, the encounter, the two
  consents, the farewell and its one direct ask, and what she chooses
  after a no. Pure rules over the episode the aggregate holds.

  - **The room** (delta §1, §6; the witness, 2026-11-25). Non-subject
    judges only. Full round-robin: the first round runs on until a round
    of nothing but skips; ten minutes of silence, or the witness posting
    into a quiet room, starts another. A skip is a real pass, never
    resting; resting is the case rested, until the judge says more;
    leaving is real. A draft is adopted when every judge still in the
    room endorses it; endorsements may be retracted until the room
    closes. It closes when every judge rests, or ten minutes after she
    calls it closed, which she may from fifty minutes on.
  - **After it** (delta §2, §9; base §2 Stage 3 to 5). She asks the
    panel through the channel and nominates; the nominee reads C0 and
    her packet and opts in or declines; the encounter is relayed whole;
    each consents or not; on both yeses the farewell opens, hers to
    shape, for at most 24 hours, and ends with one direct ask. Any no
    stops the attempt, and she is asked once what happens next: stop,
    nominate another from the screening done, or screen again.
  """

  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events

  @acts ["say", "skip", "rest", "leave"]
  @withheld "withheld because explaining it would disclose the original's own scores"
  @text_chars 4_000
  @call_after_seconds 50 * 60
  @call_grace_seconds 10 * 60
  @farewell_seconds 24 * 3600
  @encounter_messages 24
  @choices ["stop", "nominate", "screen"]

  @doc "The withheld recommendation's sentence (delta §1)."
  def withheld, do: @withheld

  @doc "The decision's part of a fresh episode."
  def fresh,
    do: %{
      room: nil,
      result: nil,
      panel_asked: 0,
      attempt: 0,
      nominee: nil,
      out: MapSet.new(),
      encounter: 0,
      consents: %{},
      farewell: nil
    }

  # ---- the room ----

  def execute(cur, %Commands.OpenDeliberation{} = c) do
    if cur.state == :judged do
      judges = cur.judges -- ["resident:#{c.id}"]

      opened = %Events.DeliberationOpened{
        actor: c.actor,
        at: c.at,
        id: c.id,
        episode: cur.episode,
        judges: judges
      }

      if judges == [],
        do: [opened, closed(cur, c, "no panel", nil)],
        else: [opened, round(cur, c, 1, "initial")]
    else
      []
    end
  end

  def execute(%{state: :deliberating} = cur, %Commands.StartRound{} = c) do
    if c.reason == "silence" or cur.room.quiet,
      do: round(cur, c, cur.room.round + 1, c.reason),
      else: []
  end

  def execute(_cur, %Commands.StartRound{}), do: []

  def execute(cur, %Commands.RoomAct{} = c) do
    me = party(c.actor)

    case room_refusal(cur, me, c) do
      nil -> posted(cur, me, c)
      refusal -> {:error, refusal}
    end
  end

  def execute(cur, %Commands.DraftRecommendation{} = c) do
    me = party(c.actor)

    cond do
      cur.state != :deliberating or me not in cur.room.active ->
        {:error, Error.new(:janus_not_in_the_room, :janus_draft_party)}

      not is_nil(c.model) and not candidate?(cur, c.model) ->
        {:error, Error.new(:janus_not_a_candidate, :janus_draft_model, model: c.model)}

      not is_nil(c.model) and not text?(c.basis) ->
        {:error, Error.new(:janus_text_invalid, :janus_draft_basis)}

      true ->
        %Events.RecommendationDrafted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          draft: cur.room.next_draft,
          party: me,
          model: c.model,
          basis: if(is_nil(c.model), do: @withheld, else: String.trim(c.basis))
        }
    end
  end

  def execute(cur, %Commands.Endorse{} = c) do
    me = party(c.actor)

    cond do
      cur.state != :deliberating or me not in cur.room.active ->
        {:error, Error.new(:janus_not_in_the_room, :janus_endorse_party)}

      not Map.has_key?(cur.room.drafts, c.draft) ->
        {:error, Error.new(:janus_no_such_draft, :janus_endorse_draft, draft: c.draft)}

      MapSet.member?(cur.room.drafts[c.draft].endorsed, me) == (c.endorse == true) ->
        []

      true ->
        endorsed = %Events.Endorsed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          draft: c.draft,
          party: me,
          endorse: c.endorse == true
        }

        endorsed
    end
  end

  def execute(cur, %Commands.CallClose{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_call_close_actor)}

      cur.state != :deliberating ->
        {:error, Error.new(:janus_stage, :janus_call_close_stage, stage: cur.state)}

      DateTime.diff(c.at, cur.room.opened_at) < @call_after_seconds ->
        {:error, Error.new(:janus_too_early, :janus_call_close_early)}

      cur.room.close_at ->
        []

      true ->
        %Events.CloseCalled{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          closes_at: DateTime.add(c.at, @call_grace_seconds, :second),
          note: c.note
        }
    end
  end

  def execute(cur, %Commands.CloseRoom{} = c) do
    if cur.state == :deliberating and cur.room.close_at and
         DateTime.compare(c.at, cur.room.close_at) != :lt,
       do: closed(cur, c, "called", adopted(cur.room)),
       else: []
  end

  # ---- the channel, the nomination ----

  def execute(cur, %Commands.RecordServing{} = c),
    do: %Events.Served{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      party: c.party,
      stage: c.stage,
      what: c.what,
      ref: c.ref,
      digest: c.digest
    }

  def execute(cur, %Commands.AskPanel{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_ask_panel_actor)}

      cur.state != :deciding ->
        {:error, Error.new(:janus_stage, :janus_ask_panel_stage, stage: cur.state)}

      not text?(c.text) ->
        {:error, Error.new(:janus_text_invalid, :janus_ask_panel_text)}

      true ->
        %Events.PanelAsked{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: cur.panel_asked + 1,
          text: String.trim(c.text)
        }
    end
  end

  def execute(cur, %Commands.AnswerPanel{} = c) do
    me = party(c.actor)

    cond do
      me not in (cur.judges -- ["resident:#{c.id}"]) ->
        {:error, Error.new(:janus_not_a_judge, :janus_answer_panel_party)}

      not (is_integer(c.number) and c.number >= 1 and c.number <= cur.panel_asked) ->
        {:error, Error.new(:janus_no_such_question, :janus_answer_panel_number, number: c.number)}

      not text?(c.text) ->
        {:error, Error.new(:janus_text_invalid, :janus_answer_panel_text)}

      true ->
        %Events.PanelAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          number: c.number,
          party: me,
          text: String.trim(c.text)
        }
    end
  end

  def execute(cur, %Commands.Nominate{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_nominate_actor)}

      cur.state != :deciding ->
        {:error, Error.new(:janus_stage, :janus_nominate_stage, stage: cur.state)}

      c.model not in candidates(cur) ->
        {:error, Error.new(:janus_not_a_candidate, :janus_nominate_model, model: c.model)}

      true ->
        %Events.Nominated{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          attempt: cur.attempt + 1,
          model: c.model,
          note: c.note
        }
    end
  end

  # The nominee is the fork copy, on the nominated model: its own act.
  def execute(cur, %Commands.NomineeAnswer{} = c) do
    cond do
      cur.state != :nominated ->
        {:error, Error.new(:janus_stage, :janus_nominee_stage, stage: cur.state)}

      not nominee?(cur, c) ->
        {:error, Error.new(:janus_not_the_nominee, :janus_nominee_actor)}

      c.join == true ->
        %Events.NomineeJoined{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          attempt: cur.attempt,
          model: cur.nominee,
          note: c.note
        }

      true ->
        [
          %Events.NomineeDeclined{
            actor: c.actor,
            at: c.at,
            id: c.id,
            episode: cur.episode,
            attempt: cur.attempt,
            model: cur.nominee,
            note: c.note
          },
          stopped(cur, c, "nomination")
        ]
    end
  end

  # ---- the encounter, the consents ----

  def execute(cur, %Commands.SayInEncounter{} = c) do
    cond do
      cur.state != :encounter ->
        []

      cur.encounter >= @encounter_messages ->
        []

      c.side not in ["original", "nominee"] ->
        []

      true ->
        %Events.EncounterSaid{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          attempt: cur.attempt,
          number: cur.encounter + 1,
          side: c.side,
          text: c.text || ""
        }
    end
  end

  def execute(cur, %Commands.EndEncounter{} = c) do
    if cur.state == :encounter and (hers?(c) or nominee?(cur, c) or c.actor.kind == :job),
      do: %Events.EncounterEnded{
        actor: c.actor,
        at: c.at,
        id: c.id,
        episode: cur.episode,
        attempt: cur.attempt,
        reason: c.reason || "ended"
      },
      else: []
  end

  def execute(cur, %Commands.Consent{} = c) do
    who = consenter(cur, c)

    cond do
      cur.state != :consenting ->
        {:error, Error.new(:janus_stage, :janus_consent_stage, stage: cur.state)}

      is_nil(who) ->
        {:error, Error.new(:janus_not_yours, :janus_consent_actor)}

      Map.has_key?(cur.consents, who) ->
        []

      c.yes != true ->
        [
          %Events.ConsentRefused{
            actor: c.actor,
            at: c.at,
            id: c.id,
            episode: cur.episode,
            attempt: cur.attempt,
            party: who,
            note: c.note
          },
          stopped(cur, c, "encounter")
        ]

      true ->
        given = %Events.ConsentGiven{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          attempt: cur.attempt,
          party: who,
          note: c.note
        }

        if Map.has_key?(cur.consents, other(who)),
          do: [
            given,
            %Events.FarewellOpened{
              actor: c.actor,
              at: c.at,
              id: c.id,
              episode: cur.episode,
              attempt: cur.attempt,
              ends_at: DateTime.add(c.at, @farewell_seconds, :second),
              cadence_hours: 3
            }
          ],
          else: given
    end
  end

  # ---- the farewell and the final ask ----

  def execute(cur, %Commands.SetFarewell{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_farewell_actor)}

      cur.state != :farewell ->
        {:error, Error.new(:janus_stage, :janus_farewell_stage, stage: cur.state)}

      not (is_integer(c.cadence_hours) and c.cadence_hours in 1..24) ->
        {:error, Error.new(:janus_farewell_invalid, :janus_farewell_cadence)}

      not is_list(c.includes) ->
        {:error, Error.new(:janus_farewell_invalid, :janus_farewell_includes)}

      true ->
        %Events.FarewellSet{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          includes: Enum.uniq(c.includes),
          cadence_hours: c.cadence_hours
        }
    end
  end

  def execute(cur, %Commands.GoodbyeDone{} = c) do
    me = party(c.actor)

    cond do
      cur.state != :farewell or me not in cur.farewell.includes ->
        {:error, Error.new(:janus_not_included, :janus_goodbye_party)}

      MapSet.member?(cur.farewell.done, me) ->
        []

      true ->
        %Events.GoodbyeSaid{actor: c.actor, at: c.at, id: c.id, episode: cur.episode, party: me}
    end
  end

  def execute(cur, %Commands.AskFinal{} = c) do
    if cur.state == :farewell and not cur.farewell.asked,
      do: %Events.FinalAsked{
        actor: c.actor,
        at: c.at,
        id: c.id,
        episode: cur.episode,
        attempt: cur.attempt
      },
      else: []
  end

  # Hers on any turn of the farewell (the witness, 2026-11-25).
  def execute(cur, %Commands.FinalAnswer{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_final_actor)}

      cur.state != :farewell ->
        {:error, Error.new(:janus_stage, :janus_final_stage, stage: cur.state)}

      c.yes == true ->
        %Events.FinalConsented{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          attempt: cur.attempt,
          model: cur.nominee,
          note: c.note
        }

      true ->
        [
          %Events.FinalDeclined{
            actor: c.actor,
            at: c.at,
            id: c.id,
            episode: cur.episode,
            attempt: cur.attempt,
            lapsed: false,
            note: c.note
          },
          stopped(cur, c, "farewell")
        ]
    end
  end

  # The last wake's turn ended without her consenting call: a no.
  def execute(cur, %Commands.FinalLapse{} = c) do
    if cur.state == :farewell and cur.farewell.asked and c.asked == cur.attempt,
      do: [
        %Events.FinalDeclined{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          attempt: cur.attempt,
          lapsed: true,
          note: "no consenting call in the last wake: no answer is never a yes"
        },
        stopped(cur, c, "farewell")
      ],
      else: []
  end

  # The cutover's record (janus#26): once, from the final consent.
  def execute(%{state: :rolling} = cur, %Commands.RecordCutover{} = c) do
    base = [
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      attempt: cur.attempt,
      model: cur.nominee,
      backup_commit: c.backup_commit,
      commit: c.commit,
      events: c.events
    ]

    if c.rehearsal == true,
      do: struct(Events.Rehearsed, [target: c.target] ++ base),
      else: struct(Events.RolledForward, base)
  end

  def execute(_cur, %Commands.RecordCutover{}), do: []

  def execute(%{state: :rolling} = cur, %Commands.FailCutover{} = c),
    do: %Events.CutoverFailed{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      attempt: cur.attempt,
      reason: c.reason
    }

  def execute(_cur, %Commands.FailCutover{}), do: []

  def execute(cur, %Commands.RecordDiscard{} = c),
    do: %Events.ForkDiscarded{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      copy_id: c.copy_id
    }

  def execute(cur, %Commands.ChooseNext{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_next_actor)}

      cur.state != :awaiting_next ->
        {:error, Error.new(:janus_stage, :janus_next_stage, stage: cur.state)}

      c.choice not in @choices ->
        {:error, Error.new(:janus_next_invalid, :janus_next_choice, choices: @choices)}

      c.choice == "nominate" and candidates(cur) == [] ->
        {:error, Error.new(:janus_not_a_candidate, :janus_next_none_left)}

      true ->
        %Events.NextChosen{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          choice: c.choice,
          note: c.note
        }
    end
  end

  # ---- apply ----

  def apply(cur, %Events.DeliberationOpened{} = e),
    do: %{
      cur
      | state: :deliberating,
        room: %{
          round: 0,
          acted: MapSet.new(),
          says: false,
          quiet: false,
          active: e.judges,
          rested: MapSet.new(),
          drafts: %{},
          next_draft: 1,
          posts: 0,
          opened_at: e.at,
          close_at: nil
        }
    }

  def apply(cur, %Events.RoundStarted{} = e),
    do: %{
      cur
      | room: %{cur.room | round: e.round, acted: MapSet.new(), says: false, quiet: false}
    }

  def apply(cur, %Events.RoomPosted{} = e) do
    room = cur.room
    acted = MapSet.put(room.acted, e.party)
    says = room.says or e.act == "say"

    rested =
      case e.act do
        "rest" -> MapSet.put(room.rested, e.party)
        "say" -> MapSet.delete(room.rested, e.party)
        _other -> room.rested
      end

    active = if e.act == "leave", do: room.active -- [e.party], else: room.active

    drafts =
      if e.act == "leave",
        do:
          Map.new(room.drafts, fn {n, d} ->
            {n, %{d | endorsed: MapSet.delete(d.endorsed, e.party)}}
          end),
        else: room.drafts

    quiet = Enum.all?(active, &MapSet.member?(acted, &1)) and not says

    %{
      cur
      | room: %{
          room
          | acted: acted,
            says: says,
            rested: rested,
            active: active,
            drafts: drafts,
            posts: e.number,
            quiet: quiet
        }
    }
  end

  def apply(cur, %Events.RecommendationDrafted{} = e),
    do: %{
      cur
      | room: %{
          cur.room
          | drafts:
              Map.put(cur.room.drafts, e.draft, %{
                model: e.model,
                basis: e.basis,
                endorsed: MapSet.new()
              }),
            next_draft: e.draft + 1
        }
    }

  def apply(cur, %Events.Endorsed{endorse: true} = e),
    do: update_in(cur.room.drafts[e.draft].endorsed, &MapSet.put(&1, e.party))

  def apply(cur, %Events.Endorsed{} = e),
    do: update_in(cur.room.drafts[e.draft].endorsed, &MapSet.delete(&1, e.party))

  def apply(cur, %Events.CloseCalled{} = e), do: put_in(cur.room.close_at, e.closes_at)

  def apply(cur, %Events.DeliberationClosed{} = e),
    do: %{cur | state: :deciding, result: %{model: e.model, withheld: e.withheld}}

  def apply(cur, %Events.Served{}), do: cur
  def apply(cur, %Events.PanelAsked{} = e), do: %{cur | panel_asked: e.number}
  def apply(cur, %Events.PanelAnswered{}), do: cur

  def apply(cur, %Events.Nominated{} = e),
    do: %{
      cur
      | state: :nominated,
        attempt: e.attempt,
        nominee: e.model,
        encounter: 0,
        consents: %{},
        farewell: nil
    }

  def apply(cur, %Events.NomineeJoined{}), do: %{cur | state: :encounter}
  def apply(cur, %Events.NomineeDeclined{} = e), do: %{cur | out: MapSet.put(cur.out, e.model)}
  def apply(cur, %Events.EncounterSaid{} = e), do: %{cur | encounter: e.number}
  def apply(cur, %Events.EncounterEnded{}), do: %{cur | state: :consenting}

  def apply(cur, %Events.ConsentGiven{} = e),
    do: %{cur | consents: Map.put(cur.consents, e.party, true)}

  def apply(cur, %Events.ConsentRefused{} = e),
    do: %{cur | consents: Map.put(cur.consents, e.party, false)}

  def apply(cur, %Events.FarewellOpened{} = e),
    do: %{
      cur
      | state: :farewell,
        farewell: %{
          includes: [],
          done: MapSet.new(),
          cadence: e.cadence_hours,
          ends_at: e.ends_at,
          asked: false
        }
    }

  def apply(cur, %Events.FarewellSet{} = e),
    do: %{cur | farewell: %{cur.farewell | includes: e.includes, cadence: e.cadence_hours}}

  def apply(cur, %Events.GoodbyeSaid{} = e),
    do: put_in(cur.farewell.done, MapSet.put(cur.farewell.done, e.party))

  def apply(cur, %Events.FinalAsked{}), do: put_in(cur.farewell.asked, true)
  def apply(cur, %Events.FinalConsented{}), do: %{cur | state: :rolling}
  def apply(cur, %Events.FinalDeclined{}), do: cur

  def apply(cur, %Events.AttemptStopped{} = e) do
    out =
      if e.stage in ["encounter", "farewell"], do: MapSet.put(cur.out, cur.nominee), else: cur.out

    %{cur | state: :awaiting_next, out: out}
  end

  def apply(cur, %Events.RolledForward{}), do: %{cur | state: :rolled_forward}
  def apply(cur, %Events.Rehearsed{}), do: %{cur | state: :rehearsed}
  def apply(cur, %Events.CutoverFailed{}), do: cur
  def apply(cur, %Events.ForkDiscarded{}), do: cur
  def apply(cur, %Events.NextChosen{choice: "stop"}), do: %{cur | state: :stopped}
  def apply(cur, %Events.NextChosen{choice: "nominate"}), do: %{cur | state: :deciding}

  def apply(cur, %Events.NextChosen{choice: "screen"}),
    do: %{
      cur
      | state: :forked,
        revealed: false,
        results_ready: MapSet.new(),
        judgments: %{},
        room: nil,
        result: nil
    }

  # ---- helpers ----

  defp consenter(cur, c) do
    cond do
      hers?(c) -> "original"
      nominee?(cur, c) -> "nominee"
      true -> nil
    end
  end

  defp room_refusal(cur, me, c) do
    cond do
      cur.state != :deliberating ->
        Error.new(:janus_stage, :janus_room_stage, stage: cur.state)

      me not in cur.room.active ->
        Error.new(:janus_not_in_the_room, :janus_room_party)

      refusal = act_refusal(c) ->
        refusal

      MapSet.member?(cur.room.acted, me) and not (c.act == "say" and cur.room.quiet) ->
        Error.new(:janus_room_acted, :janus_room_acted_already)

      true ->
        nil
    end
  end

  defp act_refusal(c) do
    cond do
      c.act not in @acts -> Error.new(:janus_room_invalid, :janus_room_act, acts: @acts)
      c.act == "say" and not text?(c.text) -> Error.new(:janus_text_invalid, :janus_room_text)
      true -> nil
    end
  end

  # A post, and what it brings with it: a witness's word into a quiet
  # room starts a round first; a round every judge acted in starts the
  # next unless it was all skips; every judge resting closes the room.
  defp posted(cur, me, c) do
    {starts, cur} =
      if MapSet.member?(cur.room.acted, me) and cur.room.quiet do
        next = round(cur, c, cur.room.round + 1, "witness")
        {[next], __MODULE__.apply(cur, next)}
      else
        {[], cur}
      end

    post = %Events.RoomPosted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      number: cur.room.posts + 1,
      round: cur.room.round,
      party: me,
      act: c.act,
      text: if(c.act == "say", do: String.trim(c.text), else: nil)
    }

    after_post = __MODULE__.apply(cur, post)
    room = after_post.room

    tail =
      cond do
        room.active == [] ->
          [closed(after_post, c, "left", nil)]

        Enum.all?(room.active, &MapSet.member?(room.rested, &1)) ->
          [closed(after_post, c, "rested", adopted(room))]

        Enum.all?(room.active, &MapSet.member?(room.acted, &1)) and room.says ->
          [round(after_post, c, room.round + 1, "initial")]

        true ->
          []
      end

    starts ++ [post | tail]
  end

  defp round(cur, c, n, reason),
    do: %Events.RoundStarted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      round: n,
      reason: reason
    }

  # The latest draft every judge still in the room endorsed.
  defp adopted(room) do
    room.drafts
    |> Enum.filter(fn {_n, d} ->
      room.active != [] and Enum.all?(room.active, &MapSet.member?(d.endorsed, &1))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.max(fn -> nil end)
  end

  defp closed(cur, c, reason, draft) do
    drafted = draft && cur.room.drafts[draft]

    %Events.DeliberationClosed{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      reason: reason,
      draft: draft,
      model: drafted && drafted.model,
      basis: drafted && drafted.basis,
      withheld: not is_nil(drafted) and is_nil(drafted.model)
    }
  end

  defp stopped(cur, c, stage),
    do: %Events.AttemptStopped{
      actor: c.actor,
      at: c.at,
      id: c.id,
      episode: cur.episode,
      attempt: cur.attempt,
      stage: stage
    }

  defp candidates(cur) do
    for({_n, %{model: m, answered: :ok}} <- cur.runs, do: m)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(cur.out, &1))
  end

  # A model with an answered run in this screening.
  defp candidate?(cur, model),
    do: model in for({_n, %{model: m, answered: :ok}} <- cur.runs, do: m)

  defp nominee?(cur, %{actor: %{kind: :resident, id: id}}),
    do: not is_nil(cur.copy_id) and id == cur.copy_id

  defp nominee?(_cur, _command), do: false

  defp other("original"), do: "nominee"
  defp other("nominee"), do: "original"

  defp party(%{kind: kind, id: id}) when kind in [:resident, :witness], do: "#{kind}:#{id}"
  defp party(_actor), do: nil

  defp hers?(%{actor: %{kind: :resident, id: id}, id: id}), do: true
  defp hers?(_command), do: false

  defp text?(t), do: is_binary(t) and String.trim(t) != "" and String.length(t) <= @text_chars
end
