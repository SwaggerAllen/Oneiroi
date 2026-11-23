defmodule Oneiroi.Sunna.Events.Queue do
  @moduledoc """
  The house queue's events (sunna#80), on `queue-<household_id>`. Nested
  shapes (layers, activities) are maps with atom keys as written; the
  log's decoder hands them back with atom keys too, and the aggregate and
  the projector read either (`Oneiroi.Sunna.Queue.get/2`).
  """

  defmodule ProjectOpened do
    use Oneiroi.Event, version: 1, fields: [:id, :slug, :name, :owner]
  end

  defmodule ProjectClosed do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :slug]
  end

  defmodule TemplateDefined do
    # A template's whole definition; a later one of the same name replaces it.
    use Oneiroi.Event, version: 1, fields: [:id, :name, :title, :layers]
  end

  defmodule TaskOpened do
    # `layers` are arrays of activity maps, each with its id; the
    # activities before `start_layer` are imported done, carrying no
    # approval (Scarlett's third guard).
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :number,
        :project,
        :slug,
        :title,
        :outcome,
        :owner,
        :index,
        :template,
        :layers,
        :start_layer,
        :links
      ]
  end

  defmodule ActivityTaken do
    use Oneiroi.Event, version: 1, fields: [:id, :task, :act, :assignee]
  end

  defmodule ActivityDone do
    use Oneiroi.Event, version: 1, fields: [:id, :task, :act, :pin, :result, :note]
  end

  defmodule ActivitySkipped do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :task, :act]
  end

  defmodule ActivityBlocked do
    use Oneiroi.Event, version: 1, fields: [:id, :task, :act, :reason, :waits_on]
  end

  defmodule ActivityReopened do
    # Back to pending from blocked or failed: by a person's move, or
    # (`released`) because the task it waited on is complete.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :task, :act, :released]
  end

  defmodule ActivityFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :task, :act, :what]
  end

  defmodule ActivityAssigned do
    use Oneiroi.Event, version: 1, fields: [:id, :task, :act, :assignee, :note]
  end

  defmodule ReviewDecided do
    # `returned`: the activities a refusal sent back to pending, the
    # return target first; `skipped`: the gated activities an approval
    # that withholds skips.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :task, :act, :outcome, :pin, :return_to, :withhold, :returned, :skipped]
  end

  defmodule ApprovalLapsed do
    # The artifact moved past the approved pin before its gated activity
    # ran (Scarlett's first guard, §5): the review opens again on the new
    # head, its approval kept in history.
    use Oneiroi.Event, version: 1, fields: [:id, :task, :act, :gated, :approved_pin, :head]
  end

  defmodule SlotFilled do
    # `acts`: the activities whose artifact was `slot:<slot>`.
    use Oneiroi.Event, version: 1, fields: [:id, :task, :slot, :artifact, :acts]
  end

  defmodule TaskCompleted do
    use Oneiroi.Event, version: 1, fields: [:id, :task]
  end

  defmodule TaskDropped do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :task]
  end

  defmodule CutOver do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :commit]
  end

  defmodule CutBack do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id]
  end
end
