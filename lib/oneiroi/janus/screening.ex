defmodule Oneiroi.Janus.Screening do
  @moduledoc """
  The panel, screening and judging (janus#12 to #15): pure rules over
  the episode the aggregate holds, as `Preparation` is.

  - **The panel.** She invites members of the household; each joins by
    their own act, or leaves; the witness is on it unless he leaves
    (the witness, 2026-11-25: he judges unless he declines, as anyone
    may). It is fixed when screening starts, never changed during it.
  - **Screening.** Hers to start, once C0 is frozen and the fork made:
    every model of the pool answers every question in the set, and her
    own model answers each as her baseline, each a one-shot run on the
    fork copy in its own thread (base §2 Stage 2; the witness: the
    baseline written exactly as if it were one of the candidates, never
    mixed into the runs). The runs arrive shuffled and numbered.
  - **Judging.** Every judge judges every answered run (the witness,
    2026-11-25), blind: one classification a run (delta §4), OBSERVED,
    or an argued DEVELOPMENT or FIDELITY ANOMALY with evidence and
    uncertainty, and a favorite or nothing. A judge may change any of
    theirs until they mark their results ready. When every judgment is
    in, who answered is revealed; when every judge is ready, judging
    closes and the judgments are locked.
  """

  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events

  @categories ["OBSERVED", "DEVELOPMENT", "FIDELITY ANOMALY"]
  @uncertainties ["low", "medium", "high"]
  @argument_chars 4_000
  @party ~r/\A(resident|witness):[0-9a-f-]{36}\z/

  @doc "The classifications a run takes: three categories, not a scale."
  def categories, do: @categories

  @doc "The panel and screening's part of a fresh episode."
  def fresh,
    do: %{
      panel: %{},
      judges: [],
      runs: %{},
      baseline: %{},
      judgments: %{},
      results_ready: MapSet.new(),
      revealed: false
    }

  @doc "An actor's party: `resident:<id>` or `witness:<id>`."
  def party(%{kind: kind, id: id}) when kind in [:resident, :witness], do: "#{kind}:#{id}"
  def party(_actor), do: nil

  # ---- the panel ----

  def execute(%{state: state}, %command{})
      when command in [Commands.InviteJudge, Commands.JoinPanel, Commands.LeavePanel] and
             state not in [:open, :forked],
      do: {:error, Error.new(:janus_stage, :janus_panel_stage, stage: state)}

  def execute(cur, %Commands.InviteJudge{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_invite_actor)}

      not (is_binary(c.party) and Regex.match?(@party, c.party)) or c.party == "resident:#{c.id}" ->
        {:error, Error.new(:janus_not_a_member, :janus_invite_party)}

      c.member != true ->
        {:error, Error.new(:janus_not_a_member, :janus_invite_member)}

      Map.get(cur.panel, c.party) in [:invited, :in] ->
        []

      true ->
        %Events.JudgeInvited{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          party: c.party
        }
    end
  end

  def execute(cur, %Commands.JoinPanel{} = c) do
    me = party(c.actor)

    cond do
      Map.get(cur.panel, me) == :in ->
        []

      # The witness joins of his own, unless she took him off (janus#48);
      # then her invitation brings him back.
      Map.get(cur.panel, me) == :invited or
          (witness?(c) and Map.get(cur.panel, me) not in [:removed, :withdrawn]) ->
        %Events.JudgeJoined{actor: c.actor, at: c.at, id: c.id, episode: cur.episode, party: me}

      true ->
        {:error, Error.new(:janus_not_invited, :janus_join_uninvited)}
    end
  end

  def execute(cur, %Commands.LeavePanel{} = c) do
    me = party(c.actor)

    if Map.get(cur.panel, me) in [:invited, :in] or (witness?(c) and is_nil(cur.panel[me])),
      do: %Events.JudgeLeft{
        actor: c.actor,
        at: c.at,
        id: c.id,
        episode: cur.episode,
        party: me,
        note: c.note
      },
      else: {:error, Error.new(:janus_not_invited, :janus_leave_absent)}
  end

  # ---- screening ----

  def execute(cur, %Commands.StartScreening{} = c) do
    cond do
      not hers?(c) ->
        {:error, Error.new(:janus_not_yours, :janus_screening_actor)}

      cur.state != :forked ->
        {:error, Error.new(:janus_stage, :janus_screening_stage, stage: cur.state)}

      not cur.frozen ->
        {:error, Error.new(:janus_not_ready_to_screen, :janus_screening_unfrozen)}

      not runs_match?(cur, c.runs) ->
        {:error, Error.new(:janus_not_ready_to_screen, :janus_screening_runs)}

      not is_binary(c.baseline_model) ->
        {:error, Error.new(:janus_not_ready_to_screen, :janus_screening_baseline)}

      true ->
        %Events.ScreeningStarted{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          runs: c.runs,
          questions: in_questions(cur),
          baseline_model: c.baseline_model,
          judges: panel_of(cur, c),
          note: c.note
        }
    end
  end

  def execute(%{state: state}, %command{})
      when command in [Commands.RecordRun, Commands.RecordBaseline] and state != :screening,
      do: []

  def execute(cur, %Commands.RecordRun{} = c) do
    case Map.get(cur.runs, c.run) do
      %{answered: nil} ->
        answered = %Events.RunAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          run: c.run,
          content: c.content,
          refusal: c.refusal == true,
          failure: c.failure
        }

        with_finish(cur, put_in(cur.runs[c.run].answered, outcome(c)), answered)

      _absent_or_answered ->
        []
    end
  end

  def execute(cur, %Commands.RecordBaseline{} = c) do
    case Map.fetch(cur.baseline, c.question) do
      {:ok, nil} ->
        answered = %Events.BaselineAnswered{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          question: c.question,
          content: c.content,
          refusal: c.refusal == true,
          failure: c.failure
        }

        with_finish(cur, put_in(cur.baseline[c.question], outcome(c)), answered)

      _absent_or_answered ->
        []
    end
  end

  # ---- judging ----

  def execute(cur, %Commands.JudgeRun{} = c) do
    me = party(c.actor)

    case judge_refusal(cur, me, c) || judgment_refusal(c) do
      nil ->
        judged = %Events.RunJudged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          party: me,
          run: c.run,
          category: c.category,
          argument: blank(c.argument),
          evidence: blank(c.evidence),
          uncertainty: blank(c.uncertainty),
          favorite: c.favorite == true
        }

        after_judging = %{cur | judgments: Map.put(cur.judgments, {me, c.run}, c.category)}

        if not cur.revealed and cur.state == :judging and complete?(after_judging),
          do: [judged, %Events.Revealed{actor: c.actor, at: c.at, id: c.id, episode: cur.episode}],
          else: judged

      refusal ->
        {:error, refusal}
    end
  end

  def execute(cur, %Commands.MarkResultsReady{} = c) do
    me = party(c.actor)

    cond do
      me not in cur.judges ->
        {:error, Error.new(:janus_not_a_judge, :janus_ready_results_party)}

      not cur.revealed ->
        {:error, Error.new(:janus_judging_open, :janus_ready_results_unrevealed)}

      MapSet.member?(cur.results_ready, me) ->
        []

      true ->
        ready = %Events.ResultsReady{
          actor: c.actor,
          at: c.at,
          id: c.id,
          episode: cur.episode,
          party: me
        }

        if MapSet.size(MapSet.put(cur.results_ready, me)) == length(cur.judges),
          do: [
            ready,
            %Events.JudgingClosed{actor: c.actor, at: c.at, id: c.id, episode: cur.episode}
          ],
          else: ready
    end
  end

  # ---- apply ----

  def apply(cur, %Events.JudgeInvited{} = e),
    do: %{cur | panel: Map.put(cur.panel, e.party, :invited)}

  def apply(cur, %Events.JudgeJoined{} = e), do: %{cur | panel: Map.put(cur.panel, e.party, :in)}
  def apply(cur, %Events.JudgeLeft{} = e), do: %{cur | panel: Map.put(cur.panel, e.party, :left)}

  def apply(cur, %Events.ScreeningStarted{} = e) do
    runs =
      Map.new(e.runs, fn r ->
        {field(r, :run), %{model: field(r, :model), question: field(r, :question), answered: nil}}
      end)

    %{
      cur
      | state: :screening,
        judges: e.judges,
        runs: runs,
        baseline: Map.new(e.questions, &{&1, nil}),
        judgments: %{},
        results_ready: MapSet.new(),
        revealed: false
    }
  end

  def apply(cur, %Events.RunAnswered{} = e),
    do: put_in(cur.runs[e.run].answered, if(e.failure, do: :failed, else: :ok))

  def apply(cur, %Events.BaselineAnswered{} = e),
    do: put_in(cur.baseline[e.question], if(e.failure, do: :failed, else: :ok))

  def apply(cur, %Events.ScreeningFinished{}), do: %{cur | state: :judging}

  def apply(cur, %Events.RunJudged{} = e),
    do: %{cur | judgments: Map.put(cur.judgments, {e.party, e.run}, e.category)}

  def apply(cur, %Events.Revealed{}), do: %{cur | revealed: true}

  def apply(cur, %Events.ResultsReady{} = e),
    do: %{cur | results_ready: MapSet.put(cur.results_ready, e.party)}

  def apply(cur, %Events.JudgingClosed{}), do: %{cur | state: :judged}

  # ---- helpers ----

  defp judge_refusal(cur, me, c) do
    cond do
      cur.state not in [:screening, :judging] ->
        Error.new(:janus_stage, :janus_judge_stage, stage: cur.state)

      me not in cur.judges ->
        Error.new(:janus_not_a_judge, :janus_judge_party)

      MapSet.member?(cur.results_ready, me) ->
        Error.new(:janus_judgments_locked, :janus_judge_locked)

      get_in(cur.runs, [c.run, :answered]) != :ok ->
        Error.new(:janus_no_such_run, :janus_judge_run, run: c.run)

      true ->
        nil
    end
  end

  # The last answer finishes screening; a judge cannot have judged every
  # run before it, so the reveal comes with a judgment, never here,
  # unless no run answered at all.
  defp with_finish(cur, after_answer, answered) do
    runs_done = Enum.all?(after_answer.runs, fn {_n, r} -> r.answered != nil end)
    baseline_done = Enum.all?(after_answer.baseline, fn {_q, b} -> b != nil end)

    if runs_done and baseline_done do
      failed = Enum.count(after_answer.runs, fn {_n, r} -> r.answered == :failed end)

      finished = %Events.ScreeningFinished{
        actor: answered.actor,
        at: answered.at,
        id: answered.id,
        episode: cur.episode,
        answered: map_size(after_answer.runs) - failed,
        failed: failed
      }

      # A last run that failed leaves nothing more to judge: if every
      # judgment is in already, who answered is shown now.
      if complete?(after_answer) and map_size(after_answer.judgments) > 0,
        do: [
          answered,
          finished,
          %Events.Revealed{
            actor: answered.actor,
            at: answered.at,
            id: answered.id,
            episode: cur.episode
          }
        ],
        else: [answered, finished]
    else
      answered
    end
  end

  defp outcome(%{failure: nil}), do: :ok
  defp outcome(_failed), do: :failed

  # Every judge has judged every run that answered: absent runs are
  # excluded, never counted (delta §4).
  defp complete?(cur) do
    answered = for {n, %{answered: :ok}} <- cur.runs, do: n
    Enum.all?(cur.judges, fn j -> Enum.all?(answered, &Map.has_key?(cur.judgments, {j, &1})) end)
  end

  defp judgment_refusal(c) do
    cond do
      c.category not in @categories ->
        Error.new(:janus_judgment_invalid, :janus_judge_category, categories: @categories)

      c.category != "OBSERVED" and not argued?(c) ->
        Error.new(:janus_judgment_invalid, :janus_judge_unargued)

      not short?(c.argument) or not short?(c.evidence) ->
        Error.new(:janus_judgment_invalid, :janus_judge_too_long)

      true ->
        nil
    end
  end

  # An interpretation is argued, with its evidence and its uncertainty
  # (base §2 Stage 3: attributed, evidence and uncertainty retained).
  defp argued?(c),
    do:
      present?(c.argument) and present?(c.evidence) and
        c.uncertainty in @uncertainties

  defp present?(t), do: is_binary(t) and String.trim(t) != ""
  defp short?(nil), do: true
  defp short?(t), do: is_binary(t) and String.length(t) <= @argument_chars
  defp blank(t) when is_binary(t), do: if(String.trim(t) == "", do: nil, else: String.trim(t))
  defp blank(_other), do: nil

  defp runs_match?(cur, runs) when is_list(runs) and runs != [] do
    pool = Map.keys(cur.pool)
    questions = in_questions(cur)
    numbers = Enum.map(runs, &field(&1, :run))
    pairs = MapSet.new(runs, &{field(&1, :model), field(&1, :question)})
    expected = MapSet.new(for m <- pool, q <- questions, do: {m, q})

    # A second screening numbers its runs after the first's (delta §9:
    # screen again), so no run number is ever reused in an episode.
    offset = cur.runs |> Map.keys() |> Enum.max(fn -> 0 end)

    pool != [] and questions != [] and pairs == expected and
      Enum.sort(numbers) == Enum.to_list((offset + 1)..(offset + length(runs)))
  end

  defp runs_match?(_cur, _runs), do: false

  defp in_questions(cur),
    do: for({n, :in} <- cur.questions, do: n) |> Enum.sort()

  # Her, everyone who joined, and the witness unless he left.
  defp panel_of(cur, c) do
    joined = for {p, :in} <- cur.panel, do: p
    witness = if c.witness && cur.panel[c.witness] in [nil, :in], do: [c.witness], else: []
    Enum.uniq(["resident:#{c.id}" | joined ++ witness])
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp hers?(%{actor: %{kind: :resident, id: id}, id: id}), do: true
  defp hers?(_command), do: false

  defp witness?(%{actor: %{kind: :witness}}), do: true
  defp witness?(_command), do: false
end
