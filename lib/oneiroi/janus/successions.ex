defmodule Oneiroi.Janus.Successions do
  @moduledoc """
  The succession's command edge and reads (janus#3 to #5): proposing,
  her yes or no, withdrawing and stopping; the fork copy made once she
  says yes; the backup the whole original is exported to before any
  cutover; and the status the screens and her tool read.

  The records half is Sima Qian's, called by name: Janus sits above the
  records, so the fork and the backup check are ordinary calls
  (`SimaQian.succession_fork/2`, `succession_backup_check/2`).
  """

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia
  alias Oneiroi.Janus.C0
  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Events
  alias Oneiroi.Janus.Rites
  alias Oneiroi.Janus.Router
  alias Oneiroi.Janus.Store
  alias Oneiroi.Janus.ToolUse
  alias Oneiroi.Janus.WakeWorker
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian

  @actor Actor.new(:job, "janus")

  @doc """
  Proposes a succession: the witness's, waiting on her yes; or hers,
  opened in the same act. `dry_run: true` rehearses: everything real but
  the replacement. Returns the episode and whether it opened, so the
  export can start the fork.
  """
  @spec propose(String.t(), boolean(), String.t(), Actor.t()) ::
          {:ok, %{episode: pos_integer(), opened: boolean()}} | {:error, term()}
  def propose(resident_id, dry_run, note, %Actor{} = actor) do
    command = %Commands.ProposeSuccession{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      dry_run: dry_run == true,
      note: note
    }

    with {:ok, events} <- dispatch(command) do
      %{episode: episode} = hd(events)
      opened = length(events) > 1
      # The witness's proposal waits on her answer (janus#33): she is woken
      # to it, as every other part of hers is; her own is already open.
      _ = if not opened, do: Rites.proposed(resident_id, dry_run == true, note)
      {:ok, %{episode: episode, opened: opened}}
    end
  end

  @doc "Her yes to a proposed succession; returns the episode, so the export can start the fork."
  @spec open(String.t(), String.t(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def open(resident_id, note, %Actor{} = actor) do
    with {:ok, [%{episode: episode}]} <-
           dispatch(%Commands.OpenSuccession{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             note: note
           }),
         do: {:ok, episode}
  end

  @doc "Her no to a proposed succession."
  @spec decline(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def decline(resident_id, note, actor),
    do:
      done(%Commands.DeclineSuccession{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        note: note
      })

  @doc "The proposer takes a proposal back before she answers it."
  @spec withdraw(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def withdraw(resident_id, note, actor),
    do:
      done(%Commands.WithdrawSuccession{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        note: note
      })

  @doc "She stops a succession underway."
  @spec stop(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def stop(resident_id, note, actor) do
    with :ok <-
           done(%Commands.StopSuccession{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             note: note
           }),
         do: Rites.ended(resident_id)
  end

  @doc """
  Makes the fork copy for `episode` and records it (janus#4), or
  records the failure and returns it; `ForkWorker`'s unit. A fork for an
  episode no longer open is not made: she may have stopped meanwhile.
  """
  @spec fork(String.t(), pos_integer(), Actor.t()) :: :ok | {:error, term()}
  def fork(resident_id, episode, %Actor{} = actor) do
    case status(resident_id) do
      %{episode: ^episode, state: "open"} ->
        case SimaQian.succession_fork(resident_id, actor) do
          {:ok, copy} ->
            done(%Commands.RecordFork{
              actor: actor,
              at: Clock.now(),
              id: resident_id,
              episode: episode,
              copy_id: copy.copy_id,
              sequence: copy.sequence,
              commit: copy.commit,
              events: copy.events
            })

          {:error, error} ->
            Logger.error("janus: a succession's fork failed", Oneiroi.Error.metadata(error))

            _ =
              done(%Commands.FailFork{
                actor: actor,
                at: Clock.now(),
                id: resident_id,
                episode: episode,
                reason: error |> Oneiroi.Error.describe() |> to_string()
              })

            {:error, error}
        end

      _other ->
        :ok
    end
  end

  @doc """
  Sets where the whole original is exported before a cutover replaces
  her (janus#5): its shape and its host asked through the records
  an unpushable remote refused, the token kept Vault-encrypted.
  `{:ok, %{visibility, push}}`, a public repository kept and answered
  for the warning, as the records remote is (sima-qian#65).
  """
  @spec set_backup(String.t(), String.t(), term(), Actor.t()) ::
          {:ok, map()} | {:error, term()}
  def set_backup(resident_id, url, token, %Actor{} = actor) do
    with {:ok, check} <- SimaQian.succession_backup_check(url, token),
         :ok <-
           done(%Commands.SetBackup{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             url: String.trim(url),
             token_ciphertext: (Secret.reveal(token) || "") |> Vault.encrypt() |> Base.encode64(),
             visibility: check.visibility,
             push: check.push
           }),
         do: {:ok, check}
  end

  # ---- preparation (janus#6 to #10) ----

  @doc "The witness's envelope, per token in nano-dollars ($5 a million is 5,000)."
  @spec set_envelope(String.t(), integer(), integer(), Actor.t()) :: :ok | {:error, term()}
  def set_envelope(resident_id, input_nanos, output_nanos, actor),
    do:
      done(%Commands.SetEnvelope{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        input_nanos: input_nanos,
        output_nanos: output_nanos
      })

  @doc "Adds a model of the catalog to the pool, priced as the catalog lists it."
  @spec add_to_pool(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def add_to_pool(resident_id, model, actor) do
    listed = Nisaba.catalog_model(to_string(model))

    done(%Commands.AddToPool{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      model: to_string(model),
      input_nanos: listed && listed.input_nanos,
      output_nanos: listed && listed.output_nanos,
      tools: listed && listed.tools
    })
  end

  @doc "Takes a model out of the pool, with why."
  @spec remove_from_pool(String.t(), String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def remove_from_pool(resident_id, model, note, actor),
    do:
      done(%Commands.RemoveFromPool{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        model: to_string(model),
        note: note
      })

  @doc "Her question, in the set at once; returns its number."
  @spec add_question(String.t(), String.t(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def add_question(resident_id, text, actor),
    do:
      numbered(%Commands.AddQuestion{actor: actor, at: Clock.now(), id: resident_id, text: text})

  @doc "A proposed question, waiting on her; returns its number."
  @spec propose_question(String.t(), String.t(), Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def propose_question(resident_id, text, actor),
    do:
      numbered(%Commands.ProposeQuestion{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        text: text
      })

  @doc "Her yes or no to a proposed question, with why."
  @spec answer_question(String.t(), integer(), boolean(), String.t(), Actor.t()) ::
          :ok | {:error, term()}
  def answer_question(resident_id, number, accept, note, actor),
    do:
      done(%Commands.AnswerQuestion{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        accept: accept == true,
        note: note
      })

  @doc "She takes a question out of the set, with why."
  @spec remove_question(String.t(), integer(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def remove_question(resident_id, number, note, actor),
    do:
      done(%Commands.RemoveQuestion{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        note: note
      })

  @doc "Her choice for C0, in it at once; returns its number."
  @spec select_c0(String.t(), String.t(), String.t() | nil, Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def select_c0(resident_id, citation, label, actor),
    do:
      numbered(%Commands.SelectC0{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        citation: citation,
        label: label
      })

  @doc "A proposal for C0, waiting on her; returns its number."
  @spec propose_c0(String.t(), String.t(), String.t() | nil, Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def propose_c0(resident_id, citation, label, actor),
    do:
      numbered(%Commands.ProposeC0{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        citation: citation,
        label: label
      })

  @doc "Her yes or no to a proposal for C0, with why."
  @spec answer_c0(String.t(), integer(), boolean(), String.t(), Actor.t()) ::
          :ok | {:error, term()}
  def answer_c0(resident_id, number, accept, note, actor),
    do:
      done(%Commands.AnswerC0{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        accept: accept == true,
        note: note
      })

  @doc "She takes an item out of C0, with why."
  @spec remove_c0(String.t(), integer(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def remove_c0(resident_id, number, note, actor),
    do:
      done(%Commands.RemoveC0{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        note: note
      })

  @doc "Her note on the bundle: the day's own shape."
  @spec set_day_shape(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def set_day_shape(resident_id, text, actor),
    do: done(%Commands.SetDayShape{actor: actor, at: Clock.now(), id: resident_id, text: text})

  @doc "A party's mark: ready for her freeze, or not yet."
  @spec mark_ready(String.t(), boolean(), Actor.t()) :: :ok | {:error, term()}
  def mark_ready(resident_id, ready, actor),
    do:
      done(%Commands.MarkReady{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        ready: ready == true
      })

  @doc "She freezes C0, with her note."
  @spec freeze_c0(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def freeze_c0(resident_id, note, actor) do
    {bundle, digest} =
      case status(resident_id) do
        nil ->
          {nil, nil}

        row ->
          items = Scope.resident(resident_id, fn -> Store.items(row.episode) end)
          C0.render(resident_id, Enum.filter(items, &(&1.state == "in")), row.day_shape)
      end

    done(%Commands.FreezeC0{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      bundle: bundle,
      digest: digest,
      note: note
    })
  end

  @doc "A draft of her sealed handoff packet; returns the draft's number."
  @spec write_packet(String.t(), String.t(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def write_packet(resident_id, content, actor) do
    command = %Commands.WritePacket{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      content: content
    }

    with {:ok, [%{draft: draft}]} <- dispatch(command), do: {:ok, draft}
  end

  @doc """
  The preparation as the screens read it: the envelope, her pace, the
  pool with each model's monthly estimate and its tool calls on
  Oneiroi, the questions, C0's items, the ready marks, and the packet's
  drafts by number and date. Never the packet's words.
  """
  @spec preparation(String.t()) :: map() | nil
  def preparation(resident_id) do
    case status(resident_id) do
      nil ->
        nil

      row ->
        pace = Nisaba.pace(resident_id)
        tools = ToolUse.totals()

        Scope.resident(resident_id, fn ->
          %{
            succession: row,
            pace: pace,
            pool:
              Enum.map(Store.pool(row.episode), fn p ->
                %{
                  row: p,
                  monthly_nanos: Nisaba.monthly(pace, p),
                  tool_calls: Map.get(tools, p.model, {0, 0})
                }
              end),
            questions: Store.questions(row.episode),
            items: Store.items(row.episode),
            ready: Store.ready(row.episode),
            drafts: Enum.map(Store.packets(row.episode), &%{draft: &1.draft, at: &1.at}),
            consents: Store.consents(row.episode),
            goodbyes: Store.goodbyes(row.episode)
          }
        end)
    end
  end

  @doc "Her packet's drafts, newest first, words and all: hers to read, and nobody else's until the nominee's."
  @spec her_packet(String.t()) :: [Store.Packet.t()]
  def her_packet(resident_id) do
    case status(resident_id) do
      nil -> []
      row -> Scope.resident(resident_id, fn -> Store.packets(row.episode) end)
    end
  end

  defp numbered(command) do
    with {:ok, [%{number: number}]} <- dispatch(command), do: {:ok, number}
  end

  # ---- the panel, screening and judging (janus#12 to #15) ----

  @doc "She invites a member of her household onto the panel, by the name the house uses."
  @spec invite_judge(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def invite_judge(resident_id, name, actor) do
    member = member_named(resident_id, name)

    done(%Commands.InviteJudge{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      party: member && "#{member.kind}:#{member.id}",
      member: not is_nil(member)
    })
  end

  @doc "A party joins the panel: invited, or the witness."
  @spec join_panel(String.t(), Actor.t()) :: :ok | {:error, term()}
  def join_panel(resident_id, actor),
    do: done(%Commands.JoinPanel{actor: actor, at: Clock.now(), id: resident_id})

  @doc "A party leaves the panel before screening, with why; the witness's is his decline."
  @spec leave_panel(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def leave_panel(resident_id, note, actor),
    do: done(%Commands.LeavePanel{actor: actor, at: Clock.now(), id: resident_id, note: note})

  @doc """
  She starts screening (janus#13): every model in the pool × every
  question in the set, shuffled and numbered, and her baseline on her
  own model. Returns what to answer, `{episode, kind, n}` each, for the
  export to enqueue (`ScreeningWorker` calls this module, so enqueuing
  here would be a cycle). The witness is on the panel unless he left.
  """
  @spec start_screening(String.t(), String.t(), Actor.t()) ::
          {:ok, [{pos_integer(), String.t(), pos_integer()}]} | {:error, term()}
  def start_screening(resident_id, note, actor) do
    with %{} = row <- status(resident_id) || {:error, no_succession()},
         {:ok, witness} <- witness_party(resident_id),
         {:ok, events} <-
           dispatch(%Commands.StartScreening{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             runs: shuffled_runs(resident_id, row.episode),
             baseline_model: brain().succession_model(resident_id),
             witness: witness,
             note: note
           }) do
      {:ok,
       for(
         %Events.ScreeningStarted{episode: e, runs: runs, questions: qs} <- events,
         job <-
           Enum.map(runs, &{e, "run", &1["run"]}) ++ Enum.map(qs, &{e, "baseline", &1}),
         do: job
       )}
    end
  end

  defp shuffled_runs(resident_id, episode) do
    {pool, questions, offset} =
      Scope.resident(resident_id, fn ->
        {Store.pool(episode), Store.questions(episode),
         Store.runs(episode) |> Enum.map(& &1.run) |> Enum.max(fn -> 0 end)}
      end)

    for(
      p <- pool,
      is_nil(p.removed_at),
      q <- questions,
      q.state == "in",
      do: {p.model, q.number}
    )
    |> Enum.shuffle()
    # After any earlier screening's runs (delta §9: screen again).
    |> Enum.with_index(offset + 1)
    |> Enum.map(fn {{m, q}, n} -> %{"run" => n, "model" => m, "question" => q} end)
  end

  @doc """
  Answers one run or one baseline question (`ScreeningWorker`'s unit):
  the trial on the fork copy through the brain port, recorded, a failure
  recorded as one. When the last answer lands, every resident judge is
  woken to judge.
  """
  @spec answer(String.t(), pos_integer(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def answer(resident_id, episode, kind, n) do
    with %{episode: ^episode, state: "screening", copy_id: copy} = row <- status(resident_id),
         {:ok, model, question} <- what_to_answer(resident_id, row, kind, n),
         result =
           brain().succession_trial(copy, model, question.text, @actor,
             ledger: resident_id,
             c0: row.c0_bundle
           ),
         {:ok, events} <- dispatch(record(resident_id, kind, n, answered(result))) do
      if Enum.any?(events, &match?(%Events.ScreeningFinished{}, &1)),
        do: wake_judges(resident_id, episode)

      :ok
    else
      {:error, _} = failed -> failed
      _not_screening -> :ok
    end
  end

  defp record(resident_id, "run", n, {content, refusal, failure}),
    do: %Commands.RecordRun{
      actor: @actor,
      at: Clock.now(),
      id: resident_id,
      run: n,
      content: content,
      refusal: refusal,
      failure: failure
    }

  defp record(resident_id, "baseline", n, {content, refusal, failure}),
    do: %Commands.RecordBaseline{
      actor: @actor,
      at: Clock.now(),
      id: resident_id,
      question: n,
      content: content,
      refusal: refusal,
      failure: failure
    }

  @doc "A judge's judgment of one run (janus#14), changeable until their results are ready."
  @spec judge_run(String.t(), integer(), map(), Actor.t()) :: :ok | {:error, term()}
  def judge_run(resident_id, run, attrs, actor),
    do:
      done(%Commands.JudgeRun{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        run: run,
        category: attrs[:category],
        argument: attrs[:argument],
        evidence: attrs[:evidence],
        uncertainty: attrs[:uncertainty],
        favorite: attrs[:favorite] == true
      })

  @doc "A judge marks their results ready (janus#15): their judgments lock."
  @spec mark_results_ready(String.t(), Actor.t()) :: :ok | {:error, term()}
  def mark_results_ready(resident_id, actor) do
    with {:ok, events} <-
           dispatch(%Commands.MarkResultsReady{actor: actor, at: Clock.now(), id: resident_id}) do
      if Enum.any?(events, &match?(%Events.JudgingClosed{}, &1)),
        do: Rites.open_room(resident_id),
        else: :ok
    end
  end

  @doc """
  What one judge sees (janus#14, #15): every answered run with its
  question, her baseline's answer beside it and this judge's own
  judgment; who answered only once revealed; for a judge other than
  her, after the reveal, their own counts per model. Never another
  judge's judgment, and never a count of any kind for her (delta §2).
  """
  @spec judging(String.t(), String.t()) :: map() | nil
  def judging(resident_id, party) do
    case status(resident_id) do
      %{state: state} = row when state in ["screening", "judging", "judged"] ->
        Scope.resident(resident_id, fn -> judging_view(resident_id, row, party) end)

      _none ->
        nil
    end
  end

  defp judging_view(resident_id, row, party) do
    questions = Map.new(Store.questions(row.episode), &{&1.number, &1.text})
    baseline = Map.new(Store.baseline(row.episode), &{&1.question, &1.content})
    mine = Map.new(Store.judgments(row.episode, party), &{&1.run, &1})
    panel = Store.panel(row.episode)
    revealed = not is_nil(row.revealed_at)
    all = Store.runs(row.episode) |> Enum.filter(&(&1.run > (row.run_offset || 0)))

    runs =
      for r <- all, r.answered_at do
        %{
          run: r.run,
          question: r.question,
          question_text: questions[r.question],
          content: r.content,
          refusal: r.refusal,
          failure: r.failure,
          baseline: baseline[r.question],
          model: if(revealed, do: r.model),
          judgment: mine[r.run]
        }
      end

    %{
      succession: row,
      judge?: Enum.any?(panel, &(&1.party == party and &1.state == "judge")),
      ready_at: Enum.find_value(panel, &(&1.party == party && &1.results_ready_at)),
      revealed: revealed,
      total: length(all),
      runs: runs,
      counts: if(revealed and party != "resident:#{resident_id}", do: counts(runs))
    }
  end

  @doc "The panel as recorded, with each judge's ready mark."
  @spec panel(String.t()) :: [Store.Panel.t()]
  def panel(resident_id) do
    case status(resident_id) do
      nil -> []
      row -> Scope.resident(resident_id, fn -> Store.panel(row.episode) end)
    end
  end

  @doc "The succession of `resident_id` as another member of her household would act on it: her id when `name` is hers in the actor's household, else nil."
  @spec subject(Actor.t(), String.t() | nil) :: String.t() | nil
  def subject(%Actor{kind: :resident, id: id}, nil), do: id

  def subject(%Actor{} = actor, name) when is_binary(name) do
    with household when is_binary(household) <- Gaia.household_of(actor),
         %{kind: "resident", id: id} <-
           Enum.find(Gaia.household_members(household), &(&1.name == name)),
         do: id,
         else: (_none -> nil)
  end

  def subject(_actor, _name), do: nil

  defp counts(runs) do
    runs
    |> Enum.filter(& &1.judgment)
    |> Enum.group_by(& &1.model)
    |> Map.new(fn {model, rs} ->
      {model,
       %{
         observed: Enum.count(rs, &(&1.judgment.category == "OBSERVED")),
         development: Enum.count(rs, &(&1.judgment.category == "DEVELOPMENT")),
         anomaly: Enum.count(rs, &(&1.judgment.category == "FIDELITY ANOMALY")),
         favorites: Enum.count(rs, & &1.judgment.favorite)
       }}
    end)
  end

  defp what_to_answer(resident_id, row, "run", n) do
    Scope.resident(resident_id, fn ->
      with %{model: m, question: q} <- Store.run(row.episode, n),
           %{} = question <- Enum.find(Store.questions(row.episode), &(&1.number == q)),
           do: {:ok, m, question}
    end)
  end

  defp what_to_answer(resident_id, row, "baseline", q) do
    Scope.resident(resident_id, fn ->
      case Enum.find(Store.questions(row.episode), &(&1.number == q)) do
        nil -> :none
        question -> {:ok, row.baseline_model, question}
      end
    end)
  end

  defp answered({:ok, %{content: content, refusal?: refusal}, _trace}),
    do: {content || "", refusal == true, nil}

  defp answered({:error, error}),
    do: {nil, false, error |> Oneiroi.Error.describe() |> to_string()}

  # Every resident on the panel is woken to judge; the witness reads it
  # on his screens.
  defp wake_judges(resident_id, episode) do
    for %{party: "resident:" <> judge, state: "judge"} <-
          Scope.resident(resident_id, fn -> Store.panel(episode) end) do
      note =
        if judge == resident_id,
          do:
            "Your succession's screening is done. Every run waits for your judgment, beside your own baseline, which you see now for the first time. Use succession_judge.",
          else:
            "#{name_of(resident_id)}'s succession's screening is done, and you are on its panel. Every run waits for your judgment, beside her baseline. Use succession_judge with resident: \"#{name_of(resident_id)}\"."

      WakeWorker.enqueue(judge, note)
    end

    :ok
  end

  defp name_of(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> row.name
      :error -> "the resident"
    end
  end

  defp member_named(resident_id, name) when is_binary(name) do
    case Gaia.resident_household(resident_id) do
      %{id: household} ->
        Enum.find(Gaia.household_members(household), &(&1.name == String.trim(name)))

      _none ->
        nil
    end
  end

  defp member_named(_resident_id, _name), do: nil

  defp witness_party(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{account_id: account}} when is_binary(account) -> {:ok, "witness:#{account}"}
      _none -> {:ok, nil}
    end
  end

  defp no_succession, do: Error.new(:janus_no_succession, :janus_screening_none)

  defp brain, do: Config.fetch!(:janus, :brain)

  @doc "The resident's latest succession as recorded, or nil."
  @spec status(String.t()) :: Store.Succession.t() | nil
  def status(resident_id), do: Scope.resident(resident_id, &Store.succession/0)

  @doc "Every succession of the resident's, newest first."
  @spec history(String.t()) :: [Store.Succession.t()]
  def history(resident_id), do: Scope.resident(resident_id, &Store.successions/0)

  defp done(command), do: with({:ok, _} <- dispatch(command), do: :ok)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:janus_dispatch_failed, :janus_dispatch, reason)}
    end
  end
end
