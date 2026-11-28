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
  alias Oneiroi.Janus.Succession
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
        case fork_copy(resident_id, actor) do
          {:ok, copy} ->
            record_fork(resident_id, episode, copy, actor)

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

  defp record_fork(resident_id, episode, copy, actor) do
    with {:ok, events} <-
           dispatch(%Commands.RecordFork{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             episode: episode,
             copy_id: copy.copy_id,
             sequence: copy.sequence,
             commit: copy.commit,
             events: copy.events
           }),
         :ok <- unless_recorded(resident_id, copy.copy_id) do
      # A replayed record records nothing and wakes nobody.
      _ = if events != [], do: wake_to_pick(resident_id)
      :ok
    end
  end

  # Another job's fork recorded first (2026-11-26: two presses ran two
  # forks at once): this one's copy is nobody's, and goes (sima-qian#72).
  defp unless_recorded(resident_id, copy_id) do
    case status(resident_id) do
      %{copy_id: ^copy_id} -> :ok
      _another -> with {:ok, _} <- SimaQian.succession_remove(copy_id), do: :ok
    end
  end

  # Held while `JANUS_FORKS` is off (janus#34): the copy is never made,
  # and the fork is recorded failed, saying why.
  defp fork_copy(resident_id, actor) do
    if Config.fetch!(:janus, :forks),
      do: SimaQian.succession_fork(resident_id, actor),
      else: {:error, Error.new(:janus_forks_held, :janus_fork_held)}
  rescue
    # A copy that raises is recorded as failed like one that refuses
    # (janus#35): a crash once left the page saying "being made" for good.
    exception -> {:error, Error.caught(:janus_dispatch_failed, :janus_fork_raised, exception)}
  end

  @doc """
  The fork made again (janus#35), in its job: what a crashed fork left
  behind is swept away first (sima-qian#72), every copy a succession of
  hers recorded kept, then the fork is made. Never in the witness's
  request: a sweep of several copies outlasts it.
  """
  @spec sweep_and_fork(String.t(), pos_integer(), Actor.t()) :: :ok | {:error, term()}
  def sweep_and_fork(resident_id, episode, %Actor{} = actor) do
    case status(resident_id) do
      %{episode: ^episode, state: "open", copy_id: nil} ->
        keep = for s <- history(resident_id), is_binary(s.copy_id), do: s.copy_id
        {:ok, _swept} = SimaQian.succession_sweep(resident_id, keep)
        fork(resident_id, episode, actor)

      _other ->
        :ok
    end
  end

  @doc """
  Makes the fork again (janus#35): the witness's, for an open succession
  with no fork recorded, after a failure or a job that never finished.
  """
  @spec retry_fork(String.t(), Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  def retry_fork(resident_id, %Actor{kind: :witness} = actor) do
    case status(resident_id) do
      %{state: "open", copy_id: nil, episode: episode} ->
        with :ok <-
               done(%Commands.RetryFork{
                 actor: actor,
                 at: Clock.now(),
                 id: resident_id,
                 episode: episode
               }),
             do: {:ok, episode}

      %{} ->
        {:error, Error.new(:janus_stage, :janus_fork_retry_stage)}

      nil ->
        {:error, no_succession()}
    end
  end

  def retry_fork(_resident_id, _actor),
    do: {:error, Error.new(:janus_not_yours, :janus_fork_retry_witness_only)}

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
  @spec set_envelope(String.t(), integer(), integer(), pos_integer() | nil, Actor.t()) ::
          :ok | {:error, term()}
  def set_envelope(resident_id, input_nanos, output_nanos, max_models, actor) do
    with :ok <-
           done(%Commands.SetEnvelope{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             input_nanos: input_nanos,
             output_nanos: output_nanos,
             max_models: max_models
           }) do
      # Stated or restated with the fork made, it wakes her to pick
      # inside it; stated first, the fork's record does (janus#37).
      _ = wake_to_pick(resident_id)
      :ok
    end
  end

  # Her wake to pick models (janus#37): once both the fork and the
  # envelope are there, from whichever lands second, and again on a
  # restated envelope.
  defp wake_to_pick(resident_id) do
    case status(resident_id) do
      %{state: "forked", envelope_input_nanos: i} = row when is_integer(i) ->
        Rites.envelope_set(resident_id, i, row.envelope_output_nanos, row.envelope_max_models)

      _not_both ->
        :ok
    end
  end

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
  def select_c0(resident_id, citation, label, actor) do
    with :ok <- readable_by_her(resident_id, citation),
         do:
           numbered(%Commands.SelectC0{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             citation: citation,
             label: label
           })
  end

  @doc "A proposal for C0, waiting on her; returns its number."
  @spec propose_c0(String.t(), String.t(), String.t() | nil, Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  def propose_c0(resident_id, citation, label, actor) do
    with :ok <- readable_by_her(resident_id, citation),
         do:
           numbered(%Commands.ProposeC0{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             citation: citation,
             label: label
           })
  end

  # A record of the house goes into C0 only when she can read it as it
  # stands (janus#43): her house, an audience that holds her. Her own
  # records are read at the freeze, as before.
  defp readable_by_her(resident_id, citation) when is_binary(citation) do
    case C0.house_words(resident_id, citation) do
      {:ok, _content} -> :ok
      :not_house -> :ok
      {:error, _} -> {:error, Error.new(:janus_c0_unreadable, :janus_c0_house_unreadable)}
    end
  end

  defp readable_by_her(_resident_id, _citation), do: :ok

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

  @doc """
  A judge's own mark (janus#48): ready, or false for not yet, for one act,
  `action` "questions" (her set's close) or "c0" (her freeze, the
  default), against `version` (the artifact's version now when not
  named). The last seat ready wakes her: the act stays hers.
  """
  @spec mark_ready(String.t(), boolean(), Actor.t(), keyword()) :: :ok | {:error, term()}
  def mark_ready(resident_id, ready, actor, opts \\ []) do
    action = Keyword.get(opts, :action) || "c0"

    with :ok <-
           done(%Commands.MarkReady{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             ready: ready == true,
             action: action,
             version: Keyword.get(opts, :version)
           }) do
      _ = if ready == true, do: wake_if_all_ready(resident_id, action)
      :ok
    end
  end

  @doc "Her waiver of one seat's mark for one act, at the version now, with her note (janus#48); the seat is named as the house names it."
  @spec waive_seat(String.t(), String.t(), String.t(), String.t(), Actor.t()) ::
          :ok | {:error, term()}
  def waive_seat(resident_id, action, name, note, actor) do
    with :ok <- noted(note),
         {:ok, party} <- seat_named(resident_id, name),
         {:ok, witness} <- witness_party(resident_id),
         :ok <-
           done(%Commands.WaiveSeat{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             action: action,
             party: party,
             witness: witness,
             note: note
           }) do
      _ = wake_if_all_ready(resident_id, action)
      :ok
    end
  end

  @doc """
  Her removal door (janus#48): a seat that blocks the gate standing open,
  by the name the house uses, its invitation withdrawn or the judge taken
  off her panel, with her note.
  """
  @spec remove_judge(String.t(), String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def remove_judge(resident_id, name, note, actor) do
    with :ok <- noted(note),
         {:ok, party} <- seat_named(resident_id, name),
         {:ok, witness} <- witness_party(resident_id),
         :ok <-
           done(%Commands.RemoveJudge{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             party: party,
             witness: witness,
             note: note
           }) do
      _ = wake_if_all_ready(resident_id, gate_open(resident_id))
      :ok
    end
  end

  @doc "She enters her question window (janus#48): the set as it stands, every judge on her panel woken to read it and mark ready for its close."
  @spec open_questions(String.t(), String.t() | nil, Actor.t()) :: :ok | {:error, term()}
  def open_questions(resident_id, note, actor) do
    with :ok <-
           done(%Commands.OpenQuestions{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             note: note
           }) do
      Rites.ask_ready(resident_id, resident_judges(resident_id, "questions"), "questions")
    end
  end

  @doc "She reopens her closed question set (janus#48), with her note: its marks and waivers lapse, and her judges are asked again."
  @spec reopen_questions(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def reopen_questions(resident_id, note, actor) do
    with :ok <- noted(note),
         :ok <-
           done(%Commands.ReopenQuestions{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             note: note
           }) do
      Rites.ask_again(resident_id, resident_judges(resident_id, "questions"), note, "questions")
    end
  end

  # Her choices for C0 made, her judges in the house are asked to read
  # it and sign off (janus#45).
  defp ask_ready(resident_id, "c0"),
    do: Rites.ask_ready(resident_id, resident_judges(resident_id, "c0"), "c0")

  defp ask_ready(_resident_id, _step), do: :ok

  @doc """
  The seats a gate reads (janus#48), for `action` "questions" (her set's
  close) or "c0" (her freeze): every invited and accepted party, and her
  witness unless he left or she took him off; each with its `state`
  ("invited", "in"), its `mark` (true, false for not yet, nil for none,
  at the artifact's version now), whether she `waived` it, and `ready`:
  whether it passes the gate.
  """
  @spec seats(String.t(), String.t()) :: [map()]
  def seats(resident_id, action) do
    case status(resident_id) do
      nil ->
        []

      row ->
        {panel, marks} =
          Scope.resident(resident_id, fn ->
            {Store.panel(row.episode), Store.marks(row.episode)}
          end)

        version = if action == "questions", do: row.questions_version, else: row.c0_version

        mine =
          for m <- marks, m.action == action, m.version == version, do: {{m.party, m.kind}, m}

        mine = Map.new(mine)
        states = Map.new(panel, &{&1.party, &1.state})

        named = for %{party: p, state: s} <- panel, s in ["invited", "in"], do: p

        witness =
          case witness_party(resident_id) do
            {:ok, w} when is_binary(w) -> if Map.has_key?(states, w), do: [], else: [w]
            _none -> []
          end

        for p <- Enum.uniq(witness ++ named) do
          state = Map.get(states, p, "in")
          mark = mine[{p, "mark"}] && mine[{p, "mark"}].ready
          waived = Map.has_key?(mine, {p, "waiver"})

          %{
            party: p,
            state: state,
            mark: mark,
            waived: waived,
            ready: state == "in" and (mark == true or waived)
          }
        end
    end
  end

  @doc "The seats her freeze reads (janus#45, #48): each with whether it passes, by its own mark or her waiver."
  @spec freeze_judges(String.t()) :: [%{party: String.t(), ready: boolean()}]
  def freeze_judges(resident_id),
    do:
      for(
        s <- seats(resident_id, "c0"),
        do: Map.take(s, [:party, :ready, :state, :mark, :waived])
      )

  # The residents among a gate's seats, woken in the house.
  defp resident_judges(resident_id, action),
    do: for(%{party: "resident:" <> judge, state: "in"} <- seats(resident_id, action), do: judge)

  # Her doors carry her note (janus#48), said before anything is asked.
  defp noted(note) when is_binary(note) do
    if String.trim(note) == "",
      do: {:error, Error.new(:janus_text_invalid, :janus_door_note)},
      else: :ok
  end

  defp noted(_note), do: {:error, Error.new(:janus_text_invalid, :janus_door_note)}

  # The gate standing open: her set's close until it closes, then her freeze.
  defp gate_open(resident_id) do
    case status(resident_id) do
      %{questions_done_at: nil} -> "questions"
      _closed -> "c0"
    end
  end

  # A seat by the name the house uses, or its party as given.
  defp seat_named(resident_id, name) do
    cond do
      is_binary(name) and String.match?(name, ~r/\A(resident|witness):/) -> {:ok, name}
      member = member_named(resident_id, name) -> {:ok, "#{member.kind}:#{member.id}"}
      true -> {:error, Error.new(:janus_not_a_member, :janus_seat_unnamed)}
    end
  end

  defp wake_if_all_ready(resident_id, action) do
    seats = seats(resident_id, action)

    open? =
      case {action, status(resident_id)} do
        {"c0", %{c0_frozen_at: nil}} -> true
        {"questions", %{questions_done_at: nil}} -> true
        _closed -> false
      end

    if open? and seats != [] and Enum.all?(seats, & &1.ready),
      do: Rites.all_ready(resident_id, action),
      else: :ok
  end

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

    with {:ok, witness} <- witness_party(resident_id),
         :ok <-
           done(%Commands.FreezeC0{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             bundle: bundle,
             digest: digest,
             witness: witness,
             note: note
           }) do
      # Her freeze opens her packet's sealed turn (janus#44), once: a
      # freeze after an unfreeze (janus#46) opens no second thread.
      _ = if not reopened?(resident_id), do: Rites.packet_turn(resident_id)
      :ok
    end
  end

  defp reopened?(resident_id), do: match?(%{c0_unfrozen_at: %DateTime{}}, status(resident_id))

  @doc """
  She reopens C0 before any screening ran on it (janus#46), with her
  note: the bundle and the judges' ready marks go, the items stay, and
  her judges in the house are asked to look again.
  """
  @spec unfreeze_c0(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def unfreeze_c0(resident_id, note, actor) do
    with :ok <-
           done(%Commands.UnfreezeC0{actor: actor, at: Clock.now(), id: resident_id, note: note}) do
      Rites.ask_again(resident_id, resident_judges(resident_id, "c0"), note, "c0")
    end
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
  Her word that a step of her preparation is done for now (janus#42):
  `"pool"` wakes her to write her questions, `"questions"` to choose C0.
  Once a step an episode; a second says so and wakes nobody.
  """
  @spec finish_step(String.t(), String.t(), String.t() | nil, Actor.t()) ::
          :ok | {:error, term()}
  def finish_step(resident_id, step, note, actor) do
    command = %Commands.FinishStep{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      step: step,
      note: note,
      witness: with({:ok, w} <- witness_party(resident_id), do: w, else: (_ -> nil))
    }

    case dispatch(command) do
      {:ok, []} ->
        {:error, Error.new(:janus_already_answered, :janus_step_again, step: step)}

      {:ok, _events} ->
        _ = Rites.step_finished(resident_id, step)
        ask_ready(resident_id, step)

      {:error, _} = refused ->
        refused
    end
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
        current = current_model(resident_id, pace)

        Scope.resident(resident_id, fn ->
          %{
            succession: row,
            pace: pace,
            current: current,
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
            marks: Store.marks(row.episode),
            drafts: Enum.map(Store.packets(row.episode), &%{draft: &1.draft, at: &1.at}),
            consents: Store.consents(row.episode),
            goodbyes: Store.goodbyes(row.episode)
          }
        end)
    end
  end

  # Her model now, as the catalog prices it, and a month of her pace on
  # it (janus#38): the line the envelope is set against.
  defp current_model(resident_id, pace) do
    with model when is_binary(model) <- brain().succession_model(resident_id),
         %{} = listed <- Nisaba.catalog_model(model) do
      %{
        model: model,
        input_nanos: listed.input_nanos,
        output_nanos: listed.output_nanos,
        monthly_nanos: Nisaba.monthly(pace, listed)
      }
    else
      nil ->
        nil

      model when is_binary(model) ->
        %{model: model, input_nanos: nil, output_nanos: nil, monthly_nanos: nil}
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

  # The number the command's own event gave; a lapse may ride with it
  # (janus#48).
  defp numbered(command) do
    with {:ok, [%{number: number} | _lapsed]} <- dispatch(command), do: {:ok, number}
  end

  # ---- the panel, screening and judging (janus#12 to #15) ----

  @doc "She invites a member of her household onto the panel, by the name the house uses."
  @spec invite_judge(String.t(), String.t(), Actor.t()) :: :ok | {:error, term()}
  def invite_judge(resident_id, name, actor) do
    member = member_named(resident_id, name)

    with :ok <-
           done(%Commands.InviteJudge{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             party: member && "#{member.kind}:#{member.id}",
             member: not is_nil(member)
           }) do
      # A resident invited is woken to answer it (janus#45): joining is
      # theirs, and an invitation nobody hears is never answered.
      _ = if match?(%{kind: "resident"}, member), do: Rites.invited(resident_id, member.id)
      :ok
    end
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

  @doc "Her household's members as seats are named: `party` and the house's `name` for each (janus#48)."
  @spec panel_names(String.t()) :: [%{party: String.t(), name: String.t()}]
  def panel_names(resident_id) do
    case Gaia.resident_household(resident_id) do
      %{id: household} ->
        for m <- Gaia.household_members(household),
            do: %{party: "#{m.kind}:#{m.id}", name: m.name}

      _none ->
        []
    end
  end

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

  @doc """
  Where the resident stands in any succession, for which of her tools
  her turns carry (janus#36): `own` her own succession's state while it
  is underway (`"proposed"` to `"rolling"`), else nil; `judging` true
  while she is invited to, or on, the panel of a housemate's succession
  that is underway; `nominee` true for the fork copy of a succession
  underway, which meets her as its nominee.
  """
  @spec involvement(String.t()) :: %{
          own: String.t() | nil,
          judging: boolean(),
          nominee: boolean()
        }
  def involvement(resident_id) do
    %{
      own: underway_state(status(resident_id)),
      judging: judging_elsewhere?(resident_id),
      nominee: fork_underway?(resident_id)
    }
  end

  defp fork_underway?(resident_id) do
    with {:ok, %{fork_of: source}} when is_binary(source) <- AgathosDaimon.fetch(resident_id),
         %{copy_id: ^resident_id} = row <- status(source) do
      is_binary(underway_state(row))
    else
      _ -> false
    end
  end

  defp underway_state(%{state: state}) do
    if state in Enum.map(Succession.underway(), &Atom.to_string/1), do: state
  end

  defp underway_state(nil), do: nil

  defp judging_elsewhere?(resident_id) do
    case Gaia.resident_household(resident_id) do
      %{id: household} ->
        household
        |> Gaia.household_members()
        |> Enum.any?(&on_panel?(&1, resident_id))

      _none ->
        false
    end
  end

  # A housemate's succession underway with her on its panel, invited or in.
  defp on_panel?(%{kind: "resident", id: id}, resident_id) when id != resident_id do
    case status(id) do
      %{state: state, episode: episode} = row when is_binary(state) ->
        is_binary(underway_state(row)) and
          Enum.any?(
            Scope.resident(id, fn -> Store.panel(episode) end),
            &(&1.party == "resident:" <> resident_id and &1.state != "left")
          )

      _none ->
        false
    end
  end

  defp on_panel?(_member, _resident_id), do: false

  @doc "Every succession of the resident's, newest first."
  @spec history(String.t()) :: [Store.Succession.t()]
  def history(resident_id), do: Scope.resident(resident_id, &Store.successions/0)

  defp done(command), do: with({:ok, _} <- dispatch(command), do: :ok)

  # The judges whose marks a change lapsed are asked to look again
  # (janus#48): the residents in the house, by a wake.
  defp lapsed(resident_id, events) do
    for %Events.MarksLapsed{} = e <- events do
      judges = for "resident:" <> judge <- e.parties, do: judge
      Rites.lapsed(resident_id, judges, e.action, e.why)
    end
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        _ = lapsed(command.id, events)
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:janus_dispatch_failed, :janus_dispatch, reason)}
    end
  end
end
