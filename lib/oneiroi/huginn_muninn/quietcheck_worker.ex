defmodule Oneiroi.HuginnMuninn.QuietcheckWorker do
  @moduledoc """
  quietcheck's hourly run (spec §6.13, P21; huginn-muninn #20): the
  report over every active resident, logged with its verdict first and
  last. Scheduled in code, on this system's queue, so it survives a
  deploy and nobody sets it up by hand. A cross-tenant job under the
  platform scope, named here (huginn-muninn #12).

  Fail-loud: a miss or the checker's own crash logs at error and ends
  the job as cancelled with the verdict as its reason, which is a row in
  `oban_jobs` and never a retry, because a liveness check that failed
  has nothing to gain from running again a minute later.
  """
  use Oneiroi.Worker, queue: :huginn_muninn_quiet, unique: [period: 600]

  alias Oneiroi.HuginnMuninn.Quietcheck

  def run(_args) do
    {status, lines} = Quietcheck.report()
    level = if status == 0, do: :info, else: :error
    Enum.each(lines, &Logger.log(level, &1))
    if status == 0, do: :ok, else: {:cancel, hd(lines)}
  end
end
