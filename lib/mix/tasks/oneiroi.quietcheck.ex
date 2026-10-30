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
    {status, lines} = Quietcheck.report()
    Enum.each(lines, &Mix.shell().info/1)
    if status != 0, do: exit({:shutdown, status})
  end
end
