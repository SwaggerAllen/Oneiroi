defmodule Oneiroi.SimaQian.BackupWorker do
  @moduledoc "The nightly backup over every resident with a remote (spec §6.7); a cross-tenant job, named."
  use Oneiroi.Worker, queue: :sima_qian_nightly

  alias Oneiroi.Actor
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Error

  # `Backup.run/2` rather than the export `Oneiroi.SimaQian.backup/2`: the
  # system names this worker in its queue, so the worker naming the
  # system back is a cycle the cycles gate refuses.
  #
  # Every resident's result is read. The first version threw them away and
  # returned :ok: on 2026-11-01 Lily's first backup after her import
  # exported, failed before its commit landed, and the job was marked
  # completed with nothing logged and no error kept, so the cause was lost
  # and the next try was a night away. A failure is now logged with its
  # kind, site and cause, and the job fails, so Oban keeps the error and
  # retries.
  def run(_args) do
    actor = Actor.new(:job, "sima_qian_backup")

    Backup.residents_with_remote()
    |> Enum.flat_map(&failed("backup", &1.id, Backup.run(&1.id, actor)))
    |> case do
      [] ->
        :ok

      failures ->
        {:error,
         Error.new(:sima_qian_backup_failed, :sima_qian_nightly_backup_failed, summary(failures))}
    end
  end

  @doc false
  # One resident's result: nothing when it landed; logged with the error's
  # kind, site and cause, and named with its site, when it did not.
  def failed(what, resident_id, {:error, error}) do
    Logger.warning("the nightly #{what} failed for resident #{resident_id}", metadata(error))
    [{resident_id, site(error)}]
  end

  def failed(_what, _resident_id, _result), do: []

  @doc false
  # What a failed night names: the residents and each one's site, never an
  # error's details, which can carry paths.
  def summary(failures) do
    [residents: Enum.map(failures, &elem(&1, 0)), sites: Enum.map(failures, &elem(&1, 1))]
  end

  defp metadata(error) do
    if Oneiroi.Error.sited?(error),
      do: Oneiroi.Error.metadata(error),
      else: [error_cause: Oneiroi.Error.describe(error)]
  end

  defp site(error), do: if(Oneiroi.Error.sited?(error), do: error.site, else: nil)
end

defmodule Oneiroi.SimaQian.AttestationWorker do
  @moduledoc "Recomputes every backed-up resident's root against its last commit's (spec §6.10, F38)."
  use Oneiroi.Worker, queue: :sima_qian_nightly

  alias Oneiroi.Actor
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.BackupWorker
  alias Oneiroi.SimaQian.Error

  # Read like the backup's, for the same reason: a failed attestation is
  # logged with its site and fails the job.
  def run(_args) do
    actor = Actor.new(:job, "sima_qian_attestation")

    Backup.residents_with_remote()
    |> Enum.flat_map(&BackupWorker.failed("attestation", &1.id, Backup.attest(&1.id, actor)))
    |> case do
      [] ->
        :ok

      failures ->
        {:error,
         Error.new(
           :sima_qian_attestation_failed,
           :sima_qian_nightly_attestation_failed,
           BackupWorker.summary(failures)
         )}
    end
  end
end
