defmodule Oneiroi.Eunomia.Successions do
  @moduledoc """
  The succession's command edge and reads (eunomia#37–#39): proposing,
  her yes or no, withdrawing and stopping; the fork copy made once she
  says yes; the backup the whole original is exported to before any
  cutover; and the status the screens and her tool read.

  The records half is Sima Qian's, which depends on this system, so it
  is reached through the records port (`EUNOMIA_SUCCESSION_RECORDS`),
  named as an atom as the trial port is (eunomia#10): `succession_fork/2`
  and `succession_backup_check/2`.
  """

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Eunomia.SuccessionCommands, as: Commands
  alias Oneiroi.Eunomia.SuccessionRouter, as: Router
  alias Oneiroi.Scope

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
  Makes the fork copy for `episode` and records it (eunomia#38), or
  records the failure and returns it; `ForkWorker`'s unit. A fork for an
  episode no longer open is not made: she may have stopped meanwhile.
  """
  @spec fork(String.t(), pos_integer(), Actor.t()) :: :ok | {:error, term()}
  def fork(resident_id, episode, %Actor{} = actor) do
    case status(resident_id) do
      %{episode: ^episode, state: "open"} ->
        case records().succession_fork(resident_id, actor) do
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
            Logger.error("eunomia: a succession's fork failed", Oneiroi.Error.metadata(error))

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
  her (eunomia#39): its shape and its host asked through the records
  port, an unpushable remote refused, the token kept Vault-encrypted.
  `{:ok, %{visibility, push}}`, a public repository kept and answered
  for the warning, as the records remote is (sima-qian#65).
  """
  @spec set_backup(String.t(), String.t(), term(), Actor.t()) ::
          {:ok, map()} | {:error, term()}
  def set_backup(resident_id, url, token, %Actor{} = actor) do
    with {:ok, check} <- records().succession_backup_check(url, token),
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

  @doc "The resident's latest succession as recorded, or nil."
  @spec status(String.t()) :: Store.Succession.t() | nil
  def status(resident_id), do: Scope.resident(resident_id, &Store.succession/0)

  @doc "Every succession of the resident's, newest first."
  @spec history(String.t()) :: [Store.Succession.t()]
  def history(resident_id), do: Scope.resident(resident_id, &Store.successions/0)

  defp records, do: Config.fetch!(:eunomia, :succession_records)

  defp done(command), do: with({:ok, _} <- dispatch(command), do: :ok)

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:eunomia_dispatch_failed, :eunomia_succession_dispatch, reason)}
    end
  end
end
