defmodule Mix.Tasks.Oneiroi.Succession.Rehearse do
  @shortdoc "Rehearses a whole succession, the real replacement at its end, on a fixture resident"
  @moduledoc """
  Runs the succession's rehearsal (janus#27): the tagged test that walks
  a fixture resident through a whole succession on the fake provider,
  the real cutover at its end, and checks that her former self was kept
  first, that under her id is the fork plus the artifacts, that her rows
  match a fresh replay, and that no byte of the process is on her.

      MIX_ENV=test mix oneiroi.succession.rehearse

  A cadence, never a gate: the `succession rehearsal` workflow runs it
  on demand, against any branch.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("test", ["--only", "rehearsal", "test/rehearsal" | args])
  end
end
