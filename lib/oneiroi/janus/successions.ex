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
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Config.Secret
  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Router
  alias Oneiroi.Janus.Store
  alias Oneiroi.Janus.ToolUse
  alias Oneiroi.Nisaba
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian

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
      {:ok, %{episode: episode, opened: length(events) > 1}}
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
  def stop(resident_id, note, actor),
    do: done(%Commands.StopSuccession{actor: actor, at: Clock.now(), id: resident_id, note: note})

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
  def freeze_c0(resident_id, note, actor),
    do: done(%Commands.FreezeC0{actor: actor, at: Clock.now(), id: resident_id, note: note})

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
            drafts: Enum.map(Store.packets(row.episode), &%{draft: &1.draft, at: &1.at})
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
