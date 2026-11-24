defmodule Oneiroi.Sunna.Work do
  @moduledoc """
  The work line's aggregate, on `work-<resident_id>` (sunna#33, #86): a
  house queue activity's run claimed and ended (one at a time, so two
  checks cannot start two), the loop's rest and its reason, said once
  per reason, and the witness's levers (the runs given back, the
  free-time wait skipped).

  The old work queue's items lived here too, until it retired (sunna#102):
  nothing records an item, an arm or an item run any more, and their
  events are kept and applied so the stream replays as it was written.
  """

  alias Oneiroi.Sunna.Commands
  alias Oneiroi.Sunna.Error
  alias Oneiroi.Sunna.Events

  defstruct next: 1,
            items: %{},
            order: [],
            running: nil,
            wrapped: false,
            rested: nil,
            armed: false,
            running_act: nil

  # A house queue activity's run (sunna#86): a claim, only when nothing
  # else runs on her line.
  def execute(%__MODULE__{running: nil, running_act: nil}, %Commands.StartActivityRun{} = c),
    do: %Events.ActivityRunStarted{
      actor: c.actor,
      at: c.at,
      id: c.id,
      household: c.household,
      task: c.task,
      act: c.act,
      session_key: c.session_key,
      day: c.day
    }

  def execute(%__MODULE__{}, %Commands.StartActivityRun{}), do: []

  def execute(%__MODULE__{running_act: act}, %Commands.EndActivityRun{act: act} = c)
      when not is_nil(act),
      do: %Events.ActivityRunEnded{
        actor: c.actor,
        at: c.at,
        id: c.id,
        act: act,
        stopped: c.stopped == true,
        cut: c.cut == true,
        moved: c.moved == true
      }

  def execute(%__MODULE__{}, %Commands.EndActivityRun{}), do: []

  # The day's runs given back (sunna#53): the witness's, with a note.
  def execute(%__MODULE__{}, %Commands.ResetWorkRuns{actor: %{kind: :witness}} = c),
    do: %Events.WorkRunsReset{actor: c.actor, at: c.at, id: c.id, note: c.note}

  def execute(%__MODULE__{}, %Commands.ResetWorkRuns{}),
    do: {:error, Error.new(:sunna_work_not_a_party, :sunna_work_reset_witness_only)}

  # The free-time wait skipped (sunna#76): the witness's alone, never hers,
  # since care outranking work is what keeps her hour from her queue.
  def execute(%__MODULE__{}, %Commands.SkipCareWait{actor: %{kind: :witness}} = c),
    do: %Events.WorkCareSkipped{actor: c.actor, at: c.at, id: c.id, note: c.note}

  def execute(%__MODULE__{}, %Commands.SkipCareWait{}),
    do: {:error, Error.new(:sunna_work_not_a_party, :sunna_work_skip_care_witness_only)}

  def execute(%__MODULE__{running: nil, rested: rested}, %Commands.RestWork{} = c) do
    if c.reason == rested or not words?(c.reason, 300),
      do: [],
      else: %Events.WorkRested{actor: c.actor, at: c.at, id: c.id, reason: c.reason}
  end

  def execute(%__MODULE__{}, %Commands.RestWork{}), do: []

  # ---- the history, applied ----

  def apply(%__MODULE__{} = s, %Events.WorkAdded{number: n}),
    do: %{
      s
      | next: n + 1,
        items: Map.put(s.items, n, %{status: "open"}),
        order: s.order ++ [n],
        rested: nil
    }

  def apply(%__MODULE__{} = s, %Events.WorkMoved{number: n, status: status} = e),
    do: %{s | items: Map.put(s.items, n, item(status, e.blocked_on)), rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkHeld{number: n}),
    do: %{s | items: Map.put(s.items, n, item("held", nil)), rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkOrdered{order: order}),
    do: %{s | order: order, rested: nil}

  def apply(%__MODULE__{} = s, %Events.WorkWrapped{number: n, status: status} = e),
    do: %{s | items: Map.put(s.items, n, item(status, e.blocked_on)), wrapped: true}

  def apply(%__MODULE__{} = s, %Events.WorkStarted{number: n}),
    do: %{
      s
      | items: Map.put(s.items, n, %{status: "in_work"}),
        running: n,
        wrapped: false,
        rested: nil
    }

  def apply(%__MODULE__{} = s, %Events.WorkRunEnded{number: n, status: status} = e),
    do: %{
      s
      | items: Map.put(s.items, n, %{status: status}),
        running: nil,
        wrapped: false,
        rested: if(e.stopped, do: stopped_rest(), else: s.rested)
    }

  def apply(%__MODULE__{} = s, %Events.WorkRested{reason: reason}), do: %{s | rested: reason}

  def apply(%__MODULE__{} = s, %Events.ActivityRunStarted{act: act}),
    do: %{s | running_act: act, rested: nil}

  def apply(%__MODULE__{} = s, %Events.ActivityRunEnded{} = e),
    do: %{s | running_act: nil, rested: if(e.stopped, do: stopped_rest(), else: s.rested)}

  def apply(%__MODULE__{} = s, %Events.WorkArmed{}), do: %{s | armed: true, rested: nil}
  def apply(%__MODULE__{} = s, %Events.WorkDisarmed{}), do: %{s | armed: false}
  # The count lives in the projection; the stream keeps the act and its note.
  def apply(%__MODULE__{} = s, %Events.WorkRunsReset{}), do: s
  def apply(%__MODULE__{} = s, %Events.WorkCareSkipped{}), do: %{s | rested: nil}

  @doc "The rest a stopped run leaves the loop in, until either party touches the queue."
  def stopped_rest,
    do: "stopped: the last run was stopped; the loop waits for the queue to be touched"

  defp item(status, blocked_on), do: %{status: status, blocked_on: blocked_on}

  defp words?(text, max),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= max
end
