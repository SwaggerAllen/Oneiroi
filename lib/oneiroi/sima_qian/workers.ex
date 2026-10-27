defmodule Oneiroi.SimaQian.BackupWorker do
  @moduledoc "The nightly backup over every resident with a remote (spec §6.7); a cross-tenant job, named."
  use Oneiroi.Worker, queue: :sima_qian_nightly

  alias Oneiroi.Actor
  alias Oneiroi.SimaQian.Backup

  # `Backup.run/2` rather than the export `Oneiroi.SimaQian.backup/2`: the
  # system names this worker in its queue, so the worker naming the
  # system back is a cycle the cycles gate refuses.
  def run(_args) do
    for row <- Backup.residents_with_remote() do
      Backup.run(row.id, Actor.new(:job, "sima_qian_backup"))
    end

    :ok
  end
end

defmodule Oneiroi.SimaQian.AttestationWorker do
  @moduledoc "Recomputes every backed-up resident's root against its last commit's (spec §6.10, F38)."
  use Oneiroi.Worker, queue: :sima_qian_nightly

  alias Oneiroi.Actor
  alias Oneiroi.SimaQian.Backup

  def run(_args) do
    for row <- Backup.residents_with_remote() do
      Backup.attest(row.id, Actor.new(:job, "sima_qian_attestation"))
    end

    :ok
  end
end
