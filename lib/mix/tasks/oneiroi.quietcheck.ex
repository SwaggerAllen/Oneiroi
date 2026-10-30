defmodule Mix.Tasks.Oneiroi.Quietcheck do
  @shortdoc "Liveness over the expected events alone, fail-loud (spec §6.13, P21)"
  @moduledoc """
  `mix oneiroi.quietcheck`

  For every active resident, the expectations quietcheck watches (the
  hour marker, the nightly pass, the weekly audit, the wash, the
  baseline) and whether each is within its cadence. The verdict is
  printed at the top and the bottom, so a truncated log still shows it;
  the exit code is 0 when nothing is missing, 1 on a miss, 2 when the
  checker itself crashed, because a checker that cannot check must say
  so by the one channel a scheduler reads.
  """
  use Mix.Task
  use Boundary, classify_to: Oneiroi.Application

  alias Oneiroi.HuginnMuninn.Quietcheck

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    {status, lines} = report()
    Enum.each(lines, &Mix.shell().info/1)
    if status != 0, do: exit({:shutdown, status})
  end

  @doc "The report as the task prints it: `{exit_status, lines}`, the verdict first and last."
  @spec report() :: {0 | 1 | 2, [String.t()]}
  def report do
    case Quietcheck.guarded(fn -> residents() end) do
      {:ok, {missing, body}} ->
        verdict =
          if missing == 0, do: "QUIETCHECK: ok", else: "QUIETCHECK: FAIL, #{missing} missing"

        {if(missing == 0, do: 0, else: 1), [verdict] ++ body ++ [verdict]}

      {:crashed, message} ->
        verdict = "QUIETCHECK: CRASHED, #{message}"
        {2, [verdict, verdict]}
    end
  end

  defp residents do
    Enum.reduce(Oneiroi.AgathosDaimon.active_residents(), {0, []}, fn row, {missing, lines} ->
      case Quietcheck.verdict(row.id) do
        {:ok, expectations} ->
          {missing, lines ++ ["#{row.slug}: ok, #{length(expectations)} expected"]}

        {:missing, misses, _expectations} ->
          {missing + length(misses),
           lines ++ Enum.map(misses, &"#{row.slug}: MISSING #{Quietcheck.describe(&1)}")}
      end
    end)
  end
end
