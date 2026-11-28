defmodule Oneiroi.Janus.WorkspaceWorker do
  @moduledoc """
  Writes one succession event's entry into its step's thread (janus#49):
  the line `Oneiroi.Janus.Workspace.entry_for/2` made in the handler,
  which saw the stream in order; each entry carries its event's place in
  the stream (`seq`), so the feed reads in order whatever order the jobs
  ran in.
  """
  use Oneiroi.Worker, queue: :janus_workspace, max_attempts: 5

  alias Oneiroi.Janus.Workspace

  def run(args), do: Workspace.write(args)
end
