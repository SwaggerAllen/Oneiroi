defmodule Oneiroi.Brain.NeedsYou.Queue do
  @moduledoc """
  The house queue (sunna#80, lily:design/queue-ia §2.5): every activity
  assigned to the witness that is ready, reviews among them, from when it
  became ready. The bell is read per resident, so a household's activity
  rings once: on the bell of the resident who owns its task, or, for a
  task the witness owns, on the household's first resident's.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Gaia
  alias Oneiroi.Sunna

  @doc "The entry kind."
  @spec kind() :: String.t()
  def kind, do: "activity"

  @impl true
  def stages, do: [%{kind: kind(), screen: "queue"}]

  @impl true
  def entries(resident_id) do
    with {:ok, %{account_id: account_id}} when is_binary(account_id) <-
           AgathosDaimon.fetch(resident_id),
         %{id: household_id, members: members} <- Gaia.resident_household(resident_id),
         true <- Sunna.queue_cut_over?(household_id) do
      residents = for m <- members, m.kind == "resident", do: "resident:#{m.id}"
      me = "resident:#{resident_id}"
      first? = List.first(residents) == me

      for c <-
            Sunna.queue_activities(household_id, %{who: "witness:#{account_id}", views: ["ready"]}),
          c.owner == me or (first? and c.owner not in residents) do
        %Entry{
          kind: kind(),
          ref: c.act,
          since: c.ready_at || c.updated_at,
          screen: "queue",
          about: %{
            task: c.task,
            task_title: c.task_title,
            project: c.project,
            type: c.type,
            artifact: c.artifact,
            subject: "#{String.capitalize(c.type)} · #{c.task_title}"
          }
        }
      end
    else
      _none -> []
    end
  end
end
