defmodule Oneiroi.Janus.Handlers.Workspace do
  @moduledoc """
  A succession's events into its workspace's step threads (janus#49):
  every event a feed carries becomes an entry, machine-written, tagged
  with its step and who made it, written by `Oneiroi.Janus.WorkspaceWorker`
  a moment later. The packet's events, and every later stage's, are in no
  feed.
  """
  use Oneiroi.Handler,
    application: Oneiroi.Commanded,
    name: "janus_workspace",
    consistency: :eventual

  require Logger

  alias Oneiroi.Apsu.Jobs
  alias Oneiroi.Janus.Workspace
  alias Oneiroi.Janus.WorkspaceWorker

  @impl Commanded.Event.Handler
  def init(config) do
    Oneiroi.Scope.put(:platform)
    {:ok, config}
  end

  # Reads nothing but the event; a line that cannot be queued is a line
  # missed, logged, never a stopped succession or a stopped handler.
  @impl Commanded.Event.Handler
  def handle(%{__struct__: module} = event, metadata) do
    with ["Oneiroi", "Janus", "Events", _] <- Module.split(module),
         %{} = args <- Workspace.entry_for(event, metadata) do
      _ = Jobs.enqueue(WorkspaceWorker, args)
    end

    :ok
  rescue
    exception ->
      e = Oneiroi.Janus.Error.caught(:janus_dispatch_failed, :janus_workspace_entry, exception)
      Logger.warning("janus: a workspace entry was not queued", Oneiroi.Error.metadata(e))
      :ok
  end
end
