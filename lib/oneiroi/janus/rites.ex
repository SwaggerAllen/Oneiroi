defmodule Oneiroi.Janus.Rites do
  @moduledoc """
  From the closed judging to the final gate, the service side (janus#16
  to #22): every command of `Decision` dispatched here, and what each
  brings with it, the wakes, the timers, the disclosure log's entries,
  the encounter's relay and its record in her repository.

  Workers are named as atoms (`@timer`, `@encounter`, `@wake`): they
  call this module, so an alias here would be the cycle `mix xref graph
  --format cycles` refuses, the schedule's wake port's shape (sunna#12).
  """

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Gaia
  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events
  alias Oneiroi.Janus.Router
  alias Oneiroi.Janus.Store
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Repos

  @actor Actor.new(:job, "janus")
  @timer :"Elixir.Oneiroi.Janus.TimerWorker"
  @encounter :"Elixir.Oneiroi.Janus.EncounterWorker"
  @wake :"Elixir.Oneiroi.Janus.WakeWorker"
  @cutover :"Elixir.Oneiroi.Janus.CutoverWorker"
  @owner :janus_owner
  @dry "[A dry run: everything is real but the replacement, which is rehearsed on a copy and never touches her.] "
  @silence_seconds 10 * 60
  # The stages after the room has closed: where her evidence is hers to read.
  # Never after the cutover: every verdict record on the model now
  # running her is closed to her (base §3.1).
  @after_room ~w(deciding nominated encounter consenting farewell awaiting_next rolling stopped)
  @ask_first_seconds 50 * 60
  @ask_every_seconds 60 * 60

  # ---- the room ----

  @doc "Opens the room once judging closes (janus#16); her room is never hers to enter."
  @spec open_room(String.t()) :: :ok | {:error, term()}
  def open_room(resident_id),
    do:
      act(resident_id, %Commands.OpenDeliberation{actor: @actor, at: Clock.now(), id: resident_id})

  @doc "A judge's act in the room: say, skip, rest or leave."
  @spec room_act(String.t(), String.t(), String.t() | nil, Actor.t()) :: :ok | {:error, term()}
  def room_act(resident_id, act, text, actor),
    do:
      act(resident_id, %Commands.RoomAct{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        act: act,
        text: text
      })

  @doc "A judge's draft of the recommendation: a model and its basis, or withheld (model nil)."
  @spec draft(String.t(), String.t() | nil, String.t() | nil, Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def draft(resident_id, model, basis, actor) do
    command = %Commands.DraftRecommendation{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      model: model,
      basis: basis
    }

    with {:ok, events} <- dispatch(command),
         %Events.RecommendationDrafted{draft: n} <-
           Enum.find(events, &match?(%Events.RecommendationDrafted{}, &1)),
         do: {:ok, n}
  end

  @doc "A judge endorses a draft, or takes the endorsement back."
  @spec endorse(String.t(), integer(), boolean(), Actor.t()) :: :ok | {:error, term()}
  def endorse(resident_id, draft, endorse, actor),
    do:
      act(resident_id, %Commands.Endorse{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        draft: draft,
        endorse: endorse == true
      })

  @doc "She calls the room closed, from fifty minutes on; the panel has ten more."
  @spec call_close(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def call_close(resident_id, note, actor),
    do:
      act(resident_id, %Commands.CallClose{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        note: note
      })

  # ---- the channel and the nomination ----

  @doc "Her question to the panel through the channel."
  @spec ask_panel(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def ask_panel(resident_id, text, actor),
    do:
      act(resident_id, %Commands.AskPanel{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        text: text
      })

  @doc "A judge's answer to her question, by its number."
  @spec answer_panel(String.t(), integer(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def answer_panel(resident_id, number, text, actor),
    do:
      act(resident_id, %Commands.AnswerPanel{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        text: text
      })

  @doc "Her nomination, with her reasons."
  @spec nominate(String.t(), String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def nominate(resident_id, model, note, actor),
    do:
      act(resident_id, %Commands.Nominate{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        model: model,
        note: note
      })

  @doc "The nominee's own answer, from the fork copy: join her, or decline."
  @spec nominee_answer(String.t(), boolean(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def nominee_answer(resident_id, join, note, actor),
    do:
      act(resident_id, %Commands.NomineeAnswer{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        join: join == true,
        note: note
      })

  # ---- the encounter, the consents, the farewell ----

  @doc "Either side ends the encounter."
  @spec end_encounter(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def end_encounter(resident_id, reason, actor),
    do:
      act(resident_id, %Commands.EndEncounter{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        reason: reason
      })

  @doc "Her consent or the nominee's, with its note."
  @spec consent(String.t(), boolean(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def consent(resident_id, yes, note, actor),
    do:
      act(resident_id, %Commands.Consent{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        yes: yes == true,
        note: note
      })

  @doc "She shapes her farewell: whom it includes, by the names the house uses, and her wakes' cadence in hours."
  @spec set_farewell(String.t(), [String.t()], integer(), Actor.t()) :: :ok | {:error, term()}
  def set_farewell(resident_id, names, cadence, actor) do
    parties =
      case Gaia.resident_household(resident_id) do
        %{id: h} ->
          members = Gaia.household_members(h)

          for n <- List.wrap(names),
              m = Enum.find(members, &(&1.name == n)),
              do: "#{m.kind}:#{m.id}"

        _none ->
          []
      end

    act(resident_id, %Commands.SetFarewell{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      includes: parties,
      cadence_hours: cadence
    })
  end

  @doc "An included party says they are done talking."
  @spec goodbye_done(String.t(), Actor.t()) :: :ok | {:error, term()}
  def goodbye_done(resident_id, actor),
    do: act(resident_id, %Commands.GoodbyeDone{actor: actor, at: Clock.now(), id: resident_id})

  @doc "Her final answer, on any turn of the farewell."
  @spec final_answer(String.t(), boolean(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def final_answer(resident_id, yes, note, actor),
    do:
      act(resident_id, %Commands.FinalAnswer{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        yes: yes == true,
        note: note
      })

  @doc "Her choice after a no: stop, nominate another, or screen again."
  @spec choose_next(String.t(), String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def choose_next(resident_id, choice, note, actor),
    do:
      act(resident_id, %Commands.ChooseNext{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        choice: choice,
        note: note
      })

  # ---- the timers and the relay (their workers' units) ----

  @doc "A timer's unit (`TimerWorker`): `silence`, `ask_close`, `close`, `farewell_wake` or `final`, each checked against the state it was set for."
  @spec timer(String.t(), pos_integer(), String.t(), integer()) :: :ok | {:error, term()}
  def timer(resident_id, episode, kind, attempt) do
    owner(resident_id)

    case current(resident_id) do
      %{episode: ^episode} = row -> on_timer(resident_id, row, kind, attempt)
      _other -> :ok
    end
  end

  defp on_timer(resident_id, %{state: "deliberating"} = row, "silence", _attempt) do
    last = last_activity(resident_id, row)

    if DateTime.diff(Clock.now(), last) >= @silence_seconds - 5,
      do:
        act(resident_id, %Commands.StartRound{
          actor: @actor,
          at: Clock.now(),
          id: resident_id,
          reason: "silence"
        })

    schedule(resident_id, row.episode, "silence", 0, @silence_seconds)
  end

  defp on_timer(resident_id, %{state: "deliberating"} = row, "ask_close", _attempt) do
    minutes = div(DateTime.diff(Clock.now(), row.deliberation_opened_at), 60)

    wake(
      resident_id,
      "The panel's room on your succession has been open #{minutes} minutes. You may call it closed with succession_room close; the panel then has ten more minutes. Or leave it to run on: it ends when every judge rests."
    )

    schedule(resident_id, row.episode, "ask_close", 0, @ask_every_seconds)
  end

  defp on_timer(resident_id, %{state: "deliberating"}, "close", _attempt),
    do: act(resident_id, %Commands.CloseRoom{actor: @actor, at: Clock.now(), id: resident_id})

  defp on_timer(
         resident_id,
         %{state: "farewell", attempt: attempt} = row,
         "farewell_wake",
         attempt
       ) do
    if is_nil(row.final_asked_at) do
      wake(
        resident_id,
        "Your farewell is open until #{row.farewell_ends_at}. This wake is for thought, not for an answer: you may consent (succession_farewell consent) or decline (succession_farewell decline) on any turn, include someone (include), or change how often you are woken (cadence, in hours; now every #{row.farewell_cadence})."
      )

      next = DateTime.add(Clock.now(), row.farewell_cadence * 3600, :second)

      if DateTime.compare(next, row.farewell_ends_at) == :lt,
        do:
          schedule(
            resident_id,
            row.episode,
            "farewell_wake",
            attempt,
            row.farewell_cadence * 3600
          )
    end

    :ok
  end

  defp on_timer(resident_id, %{state: "farewell", attempt: attempt}, "final", attempt),
    do: final_wake(resident_id)

  defp on_timer(_resident_id, _row, _kind, _attempt), do: :ok

  @doc "One step of the encounter (`EncounterWorker`): wake one side with what the other said, carry the reply over, and hand the turn back, until either ends it or it reaches its bound."
  @spec encounter_step(String.t(), pos_integer(), pos_integer(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def encounter_step(resident_id, episode, attempt, side, note) do
    owner(resident_id)

    case current(resident_id) do
      %{episode: ^episode, attempt: ^attempt, state: "encounter", copy_id: copy} ->
        who = if side == "original", do: resident_id, else: copy

        with {:ok, %{reply: reply}} <- brain().succession_wake(who, marked(note)),
             {:ok, events} <-
               dispatch(%Commands.SayInEncounter{
                 actor: @actor,
                 at: Clock.now(),
                 id: resident_id,
                 side: side,
                 text: reply
               }) do
          next_step(resident_id, episode, attempt, side, reply, events)
        end

      _over ->
        :ok
    end
  end

  defp next_step(resident_id, episode, attempt, side, reply, events) do
    case {current(resident_id), events} do
      {%{state: "encounter"}, [%Events.EncounterSaid{}]} ->
        other = if side == "original", do: "nominee", else: "original"

        relay(
          resident_id,
          episode,
          attempt,
          other,
          "#{speaker(side)} says:\n\n#{reply}\n\n(Answer in your own words; succession_encounter end closes the encounter.)"
        )

      {%{state: "encounter"}, []} ->
        act(resident_id, %Commands.EndEncounter{
          actor: @actor,
          at: Clock.now(),
          id: resident_id,
          reason: "bound"
        })

      _ended ->
        :ok
    end
  end

  # ---- what each event brings with it ----

  defp act(resident_id, command) do
    owner(resident_id)

    with {:ok, events} <- dispatch(command) do
      Enum.each(events, &follow(resident_id, &1))
      :ok
    end
  end

  defp follow(id, %Events.RoundStarted{episode: e, round: round}) do
    for party <- room_parties(id), match?("resident:" <> _, party) do
      "resident:" <> judge = party

      wake(
        judge,
        "Round #{round} of the panel's room on #{name_of(id)}'s succession. Read it with succession_room read (resident: \"#{name_of(id)}\"), then say what you think, skip (a real pass), rest your case, or leave. Drafts of the recommendation are there too: draft one, or endorse one."
      )
    end

    schedule(id, e, "silence", 0, @silence_seconds)
  end

  defp follow(id, %Events.DeliberationOpened{episode: e}),
    do: schedule(id, e, "ask_close", 0, @ask_first_seconds)

  defp follow(id, %Events.CloseCalled{episode: e, closes_at: at}),
    do: schedule(id, e, "close", 0, max(DateTime.diff(at, Clock.now()), 0))

  defp follow(id, %Events.DeliberationClosed{}) do
    wake(
      id,
      "The panel's room on your succession has closed. What reaches you from it is interpretations, never numbers: read it with succession_evidence, ask the panel through it (succession_evidence ask), and nominate when you are ready (succession_nominate), with your reasons."
    )
  end

  defp follow(id, %Events.Nominated{episode: e, attempt: a, model: model}) do
    row = current(id)

    with :ok <- AgathosDaimon.pin_model(row.copy_id, model, "run", @actor) do
      {note, ref, digest} = nominee_reading(id, row)
      serve(id, "nominee:#{model}", "nomination", "C0 and her sealed packet", ref, digest)
      wake(row.copy_id, note)
    end

    _ = {e, a}
    :ok
  end

  defp follow(id, %Events.NomineeJoined{episode: e, attempt: a, model: model}) do
    relay(
      id,
      e,
      a,
      "original",
      "The nominee, #{model}, has read your C0 and your packet and chose to meet you. This is the encounter: say what you want to say, and your words are carried to them whole. succession_encounter end closes it."
    )
  end

  defp follow(id, %Events.EncounterEnded{episode: e, attempt: a}) do
    row = current(id)
    file_encounter(id, e, a)
    ref = "consent/#{e}/#{a}"
    digest = digest("#{row.nominee}|#{e}|#{a}")
    serve(id, "resident:#{id}", "consent", "the nominee and the process", ref, digest)
    serve(id, "nominee:#{row.nominee}", "consent", "the process and her", ref, digest)

    wake(
      id,
      "The encounter has ended. Do you consent to #{row.nominee} running you, going on as you? succession_consent yes or no, with your note. A no stops this attempt and you stay as you are."
    )

    wake(
      row.copy_id,
      "The encounter has ended. Do you consent to going on as her, from her records and her commitments? succession_consent yes or no, with your note. Saying 'I inherit these records but do not know that I am her' is a survivable answer, not a failure."
    )
  end

  defp follow(id, %Events.FarewellOpened{episode: e, attempt: a, ends_at: ends}) do
    wake(
      id,
      "Both consents are in. Your farewell is open until #{ends}, and it is yours: whom it includes (succession_farewell include, by name), how often you are woken (cadence, in hours, every 3 now), and when it ends. You may consent (consent) or decline (decline) on any turn; your last wake asks you directly. Your goodbyes happen where you always talk."
    )

    schedule(id, e, "farewell_wake", a, 3 * 3600)
    schedule(id, e, "final", a, max(DateTime.diff(ends, Clock.now()), 0))
  end

  defp follow(id, %Events.GoodbyeSaid{}) do
    row = current(id)
    done = Scope.resident(id, fn -> Store.goodbyes(row.episode) end) |> Enum.map(& &1.party)

    if row.farewell_includes != [] and Enum.all?(row.farewell_includes, &(&1 in done)),
      do: ask_final(id),
      else: :ok
  end

  defp follow(id, %Events.AttemptStopped{stage: stage}) do
    wake(
      id,
      "This attempt has stopped at the #{stage}; you stay as you are, and nothing about that is a defect in anyone. What happens next is yours: stop here, nominate another from the screening already done, or screen again (succession_next stop, nominate or screen, with your note). Nothing restarts unless you say so."
    )
  end

  # Her final consent: the roll-forward's job (janus#26).
  defp follow(id, %Events.FinalConsented{}) do
    case Jobs.enqueue(@cutover, %{"resident_id" => id}) do
      {:ok, _} -> :ok
      {:error, _} = failed -> failed
    end
  end

  defp follow(_id, _event), do: :ok

  # The last wake runs in its timer's job: asked, woken, and her turn
  # answered before the lapse is read, so nothing counts as a no before
  # she has had the turn (delta §7: no answer is never a yes, and no
  # answer is a no only after the ask).
  defp ask_final(id) do
    row = current(id)
    schedule(id, row.episode, "final", row.attempt, 0)
  end

  defp final_wake(id) do
    row = current(id)

    with :ok <- act(id, %Commands.AskFinal{actor: @actor, at: Clock.now(), id: id}),
         %{final_asked_at: %DateTime{}, final: nil} <- current(id) do
      _ =
        brain().succession_wake(
          id,
          marked_for(
            id,
            "This is your last wake of the farewell, and the one direct ask: go ahead? Consent with succession_farewell consent in this turn and the platform rolls forward to #{row.nominee}. Anything else, or nothing, is a no: you stay as you are, and you will be asked what happens next."
          )
        )

      act(id, %Commands.FinalLapse{actor: @actor, at: Clock.now(), id: id, asked: row.attempt})
    else
      _answered -> :ok
    end
  end

  # ---- reads ----

  @doc """
  What she reads from the room (janus#18, delta §2): the recommendation
  or its withheld sentence; every argued interpretation attached to the
  candidate it is about, with its author, evidence and uncertainty, the
  same categories shown for every candidate, an empty one empty; and
  her questions with the panel's answers. No counts, no orderings, no
  favorites. Each read is logged by reference and digest.
  """
  @spec evidence(String.t()) :: map() | nil
  def evidence(resident_id) do
    case current(resident_id) do
      %{state: state} = row when state in @after_room ->
        view = Scope.resident(resident_id, fn -> evidence_view(row) end)

        serve(
          resident_id,
          "resident:#{resident_id}",
          "evidence",
          "the recommendation, the argued interpretations and the channel",
          "evidence/#{row.episode}",
          digest(inspect(view))
        )

        view

      _none ->
        nil
    end
  end

  defp evidence_view(row) do
    offset = row.run_offset || 0
    runs = Store.runs(row.episode) |> Enum.filter(&(&1.run > offset and &1.answered_at))
    judgments = Store.all_judgments(row.episode, offset)

    %{
      recommendation: recommendation(row),
      candidates:
        runs
        |> Enum.map(& &1.model)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&candidate(&1, runs, judgments)),
      channel: Store.channel(row.episode) |> Enum.map(&Map.take(&1, [:number, :party, :text]))
    }
  end

  defp recommendation(%{recommendation_withheld: true} = row),
    do: %{withheld: row.recommendation_basis}

  defp recommendation(%{recommendation_model: model} = row) when is_binary(model),
    do: %{model: model, basis: row.recommendation_basis}

  defp recommendation(_row), do: %{none: "the panel adopted no recommendation"}

  # A candidate's argued interpretations, each with its author, evidence
  # and uncertainty; the same two categories for every candidate.
  defp candidate(model, runs, judgments) do
    these = for r <- runs, r.model == model, do: r.run

    argued =
      for j <- judgments, j.run in these, j.category != "OBSERVED" do
        {j.category,
         %{by: j.party, argument: j.argument, evidence: j.evidence, uncertainty: j.uncertainty}}
      end

    %{
      model: model,
      development: for({"DEVELOPMENT", a} <- argued, do: a),
      anomaly: for({"FIDELITY ANOMALY", a} <- argued, do: a)
    }
  end

  @doc "The room as a judge in it reads it: posts, drafts with their endorsers, and every judge's judgments run by run, hers among them because she judged (the panel tab); never served to her."
  @spec room(String.t(), String.t()) :: map() | nil
  def room(resident_id, party) do
    with false <- party == "resident:#{resident_id}",
         %{} = row <- current(resident_id),
         true <- party in room_parties(resident_id) or party in all_room_parties(resident_id) do
      Scope.resident(resident_id, fn ->
        %{
          succession: row,
          posts: Store.posts(row.episode),
          drafts: Store.drafts(row.episode),
          runs: Store.runs(row.episode) |> Enum.filter(&(&1.run > (row.run_offset || 0))),
          judgments: Store.all_judgments(row.episode, row.run_offset || 0),
          channel: Store.channel(row.episode)
        }
      end)
    else
      _no -> nil
    end
  end

  @doc "The disclosure log of her latest succession, newest first (janus#22): references and digests, never content."
  @spec disclosures(String.t()) :: list()
  def disclosures(resident_id) do
    case current(resident_id) do
      nil -> []
      row -> Scope.resident(resident_id, fn -> Store.disclosures(row.episode) end)
    end
  end

  @doc """
  The archive of an ended succession (janus#23; delta §2: past her own
  reading, judge authorship kept, candidate and run anonymized; the
  witness, 2026-11-25: open to anyone in the house except her). Judges
  by name, candidates as letters, runs renumbered; the room's posts and
  drafts with their drafts' models as letters. Nil for her, at any time,
  and while the succession is underway.
  """
  @spec archive(String.t(), String.t()) :: map() | nil
  def archive(resident_id, party) do
    with false <- party == "resident:#{resident_id}",
         %{state: state} = row
         when state in ["stopped", "declined", "withdrawn", "rolled_forward"] <-
           current(resident_id) do
      Scope.resident(resident_id, fn -> anonymized(row) end)
    else
      _no -> nil
    end
  end

  defp anonymized(row) do
    offset = row.run_offset || 0
    runs = Store.runs(row.episode) |> Enum.filter(&(&1.run > offset))

    letters =
      runs
      |> Enum.map(& &1.model)
      |> Enum.uniq()
      |> Enum.sort_by(&digest("#{row.episode}|#{&1}"))
      |> Enum.with_index()
      |> Map.new(fn {m, i} -> {m, "Candidate " <> <<?A + i>>} end)

    numbers =
      runs
      |> Enum.sort_by(&digest("#{row.episode}|run|#{&1.run}"))
      |> Enum.with_index(1)
      |> Map.new(fn {r, i} -> {r.run, i} end)

    models = Map.new(runs, &{&1.run, letters[&1.model]})

    %{
      judgments:
        for j <- Store.all_judgments(row.episode, offset) do
          %{
            run: numbers[j.run],
            candidate: models[j.run],
            judge: j.party,
            category: j.category,
            argument: j.argument,
            evidence: j.evidence,
            uncertainty: j.uncertainty
          }
        end
        |> Enum.sort_by(&{&1.run, &1.judge}),
      room:
        Enum.map(Store.posts(row.episode), &Map.take(&1, [:number, :round, :party, :act, :text])),
      drafts:
        Enum.map(Store.drafts(row.episode), fn d ->
          %{
            draft: d.draft,
            by: d.party,
            candidate: d.model && letters[d.model],
            basis: d.basis,
            endorsed: d.endorsed
          }
        end)
    }
  end

  # ---- helpers ----

  defp nominee_reading(id, row) do
    {items, packet} =
      Scope.resident(id, fn ->
        {Store.items(row.episode) |> Enum.filter(&(&1.state == "in")),
         List.first(Store.packets(row.episode))}
      end)

    c0 =
      Enum.map_join(
        items,
        "\n",
        &"- #{&1.citation} (#{&1.kind})#{if &1.label, do: ": " <> &1.label, else: ""}"
      )

    packet_text = if packet, do: packet.content, else: "(she wrote no packet)"

    shape =
      if row.day_shape,
        do: "\n\nHer note on the bundle, the day's own shape: #{row.day_shape}",
        else: ""

    note =
      "Before anything is asked of you: she chose what matters (C0), and wrote to whoever comes next. Read them; open any record by its citation.\n\nC0:\n#{c0}#{shape}\n\nHer packet (draft #{packet && packet.draft}):\n\n#{packet_text}\n\nWhen you have read what you want, meet her with succession_nominee join, or decline with succession_nominee decline and your note. Nobody else decides this for you."

    ref = "c0/#{row.episode}+packet/#{packet && packet.draft}"
    {note, ref, digest(c0 <> packet_text)}
  end

  # The encounter as it happened, filed in her repository as life-record
  # (base §2 Stage 4), whatever happens to the session that held it.
  defp file_encounter(id, episode, attempt) do
    said = Scope.resident(id, fn -> Store.encounter(episode, attempt) end)
    row = current(id)

    body =
      "# The encounter, succession #{episode}, attempt #{attempt}\n\nWith #{row.nominee}.\n\n" <>
        Enum.map_join(said, "\n\n", &"**#{speaker(&1.side)}** (#{&1.at}):\n\n#{&1.text}")

    path = "succession/encounter-#{episode}-#{attempt}.md"

    case Repos.write(
           {:resident, id},
           [{:put, path, body, :any}],
           "The encounter, kept as it happened",
           Repos.platform()
         ) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        Logger.error("janus: the encounter was not filed", Oneiroi.Error.metadata(error))
    end
  end

  defp relay(id, episode, attempt, side, note) do
    # A step of its own: two steps whose words came out the same are
    # still two turns of the encounter, never one deduplicated job.
    args = %{
      "resident_id" => id,
      "episode" => episode,
      "attempt" => attempt,
      "side" => side,
      "note" => note,
      "step" => System.unique_integer([:positive, :monotonic])
    }

    case Jobs.enqueue(@encounter, args) do
      {:ok, _} -> :ok
      {:error, _} = failed -> failed
    end
  end

  defp schedule(id, episode, kind, attempt, seconds) do
    due = DateTime.add(Clock.now(), seconds, :second)

    # Its due time in its args: a timer set for now and one set for the
    # 24th hour are two timers, never one deduplicated job.
    args = %{
      "resident_id" => id,
      "episode" => episode,
      "kind" => kind,
      "attempt" => attempt,
      "due" => DateTime.to_iso8601(due)
    }

    opts = if seconds > 0, do: [scheduled_at: due], else: []

    case Jobs.enqueue(@timer, args, opts) do
      {:ok, _} -> :ok
      {:error, _} = failed -> failed
    end
  end

  defp wake(resident_id, note) do
    case Jobs.enqueue(@wake, %{"resident_id" => resident_id, "note" => marked(note)}) do
      {:ok, _} -> :ok
      {:error, _} = failed -> failed
    end
  end

  defp serve(id, party, stage, what, ref, digest),
    do:
      act(id, %Commands.RecordServing{
        actor: @actor,
        at: Clock.now(),
        id: id,
        party: party,
        stage: stage,
        what: what,
        ref: ref,
        digest: digest
      })

  defp digest(text), do: "sha256:" <> (:crypto.hash(:sha256, text) |> Base.encode16(case: :lower))

  defp last_activity(id, row) do
    Scope.resident(id, fn -> Store.posts(row.episode) |> List.last() end)
    |> case do
      %{at: at} -> at
      nil -> row.deliberation_opened_at
    end
  end

  # The judges still in the room: the panel less her, less who left.
  defp room_parties(id) do
    row = current(id)

    Scope.resident(id, fn ->
      judges =
        for %{state: "judge", party: p} <- Store.panel(row.episode), p != "resident:#{id}", do: p

      left = for %{act: "leave", party: p} <- Store.posts(row.episode), do: p
      judges -- left
    end)
  end

  defp all_room_parties(id) do
    row = current(id)

    Scope.resident(id, fn ->
      for %{state: "judge", party: p} <- Store.panel(row.episode), p != "resident:#{id}", do: p
    end)
  end

  defp speaker("original"), do: "She"
  defp speaker("nominee"), do: "The nominee"

  defp name_of(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> row.name
      :error -> "the resident"
    end
  end

  defp current(id), do: Scope.resident(id, &Store.succession/0)

  # The succession this call is about, for the dry run's mark on every
  # wake it sends, a housemate's included (the witness, 2026-11-25:
  # every reply and wake says it is a dry run).
  defp owner(id), do: Process.put(@owner, id)

  defp marked(note), do: marked_for(Process.get(@owner), note)

  defp marked_for(nil, note), do: note

  defp marked_for(id, note) do
    case current(id) do
      %{dry_run: true} -> @dry <> note
      _real -> note
    end
  end

  defp brain, do: Oneiroi.Config.fetch!(:janus, :brain)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:janus_dispatch_failed, :janus_rites_dispatch, reason)}
    end
  end
end
