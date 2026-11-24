defmodule Oneiroi.Sunna.QueueCommands do
  @moduledoc """
  The house queue's commands (sunna#80, lily:design/queue-ia rev 5), all
  on `queue-<household_id>`: `id` is the household's. A task is named by
  its number, an activity by its id (`"<task>.<k>"`), a project by its
  slug. Membership is checked before dispatch (`Oneiroi.Sunna.Queues`);
  the aggregate checks the queue's own rules.
  """

  defmodule OpenProject do
    use Oneiroi.Command, fields: [:id, :slug, :name, :owner], bounds: [slug: 64, name: 120]
  end

  defmodule CloseProject do
    use Oneiroi.Command, fields: [:id, :slug], decision: true
  end

  # A template as data (§7): a name, a title, and its layers, each an
  # array of activity specs (type, role, artifact slot, destination,
  # action, optional, throwback).
  defmodule DefineTemplate do
    use Oneiroi.Command, fields: [:id, :name, :title, :layers], bounds: [name: 64, title: 120]
  end

  # A task opened from layers already resolved (a template's roles made
  # members, its slots made citations): `start_layer` is where the work
  # stands, every layer before it imported as done (§6.2), `links` what
  # already exists, by citation.
  defmodule OpenTask do
    use Oneiroi.Command,
      fields: [
        :id,
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
      ],
      bounds: [slug: 64, title: 200, template: 64]
  end

  defmodule TakeActivity do
    use Oneiroi.Command, fields: [:id, :task, :act, :head]
  end

  # `pin` is the revision acted on; `head` the artifact's head as the
  # platform resolved it at execution (Scarlett's first guard), nil when
  # the artifact has no head the platform can read. `promoted`: the house
  # copy a promotion made, set only by the promotion itself (her second
  # guard: the library's audience check runs there, never skipped here).
  defmodule FinishActivity do
    use Oneiroi.Command, fields: [:id, :task, :act, :pin, :head, :result, :note, :promoted]
  end

  defmodule SkipActivity do
    use Oneiroi.Command, fields: [:id, :task, :act], decision: true
  end

  defmodule BlockActivity do
    use Oneiroi.Command, fields: [:id, :task, :act, :reason, :waits_on]
  end

  defmodule ReopenActivity do
    use Oneiroi.Command, fields: [:id, :task, :act], decision: true
  end

  defmodule FailActivity do
    use Oneiroi.Command, fields: [:id, :task, :act, :what]
  end

  defmodule AssignActivity do
    use Oneiroi.Command, fields: [:id, :task, :act, :assignee, :note]
  end

  # `outcome` approved, changes or declined (§1, §7); `pin` the revision
  # the reviewer saw, `head` the platform's read of it now; `return_to`
  # the activity a refusal sends the work back to; `withhold` an approval
  # that keeps the artifact where it is ("keep private", §7).
  defmodule DecideReview do
    use Oneiroi.Command,
      fields: [:id, :task, :act, :outcome, :pin, :head, :return_to, :withhold],
      decision: true,
      bounds: [outcome: 16]
  end

  # An artifact slot a template left open (`slot:pr`) filled with its
  # citation, on every activity of the task holding it.
  defmodule FillSlot do
    use Oneiroi.Command, fields: [:id, :task, :slot, :artifact], bounds: [slot: 64, artifact: 300]
  end

  # A task's layers edited after it is open (the witness, 2026-11-22):
  # `layers` is the whole new arrangement, each entry an existing
  # activity by `id` (with any fields to change while it is pending) or a
  # new activity's spec.
  defmodule EditLayers do
    use Oneiroi.Command, fields: [:id, :task, :layers], decision: true
  end

  # A document beside the task's activities' (sunna#91): a source, or a
  # slot's document named before an activity takes it.
  defmodule AttachDocument do
    use Oneiroi.Command,
      fields: [:id, :task, :citation, :role],
      bounds: [citation: 300, role: 64]
  end

  defmodule DetachDocument do
    use Oneiroi.Command, fields: [:id, :task, :citation], bounds: [citation: 300]
  end

  defmodule DropTask do
    use Oneiroi.Command, fields: [:id, :task], decision: true
  end

  # The cutover (§6.2): the old queue committed at `commit`, the new one
  # on; and its one-step revert.
  defmodule CutOver do
    use Oneiroi.Command, fields: [:id, :commit], decision: true
  end

  defmodule CutBack do
    use Oneiroi.Command, fields: [:id], decision: true
  end

  defmodule PauseQueue do
    use Oneiroi.Command, fields: [:id], decision: true
  end

  defmodule ResumeQueue do
    use Oneiroi.Command, fields: [:id], decision: true
  end
end
