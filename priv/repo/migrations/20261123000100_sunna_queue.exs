defmodule Oneiroi.Repo.Migrations.SunnaQueue do
  use Ecto.Migration
  import Oneiroi.Migration

  # The house queue (sunna#80): projects, tasks, activities, the history
  # of each activity's decisions, templates and the queue's own state.
  # The household's, every member's and no one resident's, so
  # platform-scoped as the household's other rows are (gaia#17).
  def change do
    projection :sunna_queue_project, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:slug, :text, null: false)
      add(:name, :text, null: false)
      add(:owner, :text, null: false)
      add(:status, :text, null: false)
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:closed_at, :utc_datetime_usec)
      add(:note, :text)
    end

    create(unique_index(:sunna_queue_project, [:household_id, :slug]))

    projection :sunna_queue_task, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:number, :integer, null: false)
      add(:project, :text, null: false)
      add(:slug, :text, null: false)
      add(:title, :text, null: false)
      add(:outcome, :text, null: false)
      add(:owner, :text, null: false)
      add(:index_doc, :text, null: false)
      add(:template, :text)
      add(:links, {:array, :text}, null: false, default: [])
      add(:status, :text, null: false)
      add(:open_layer, :integer)
      add(:opened_by, :text, null: false)
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)
      add(:note, :text)
    end

    create(unique_index(:sunna_queue_task, [:household_id, :number]))

    projection :sunna_queue_activity, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:act_id, :text, null: false)
      add(:task, :integer, null: false)
      add(:layer, :integer, null: false)
      add(:position, :integer, null: false)
      add(:type, :text, null: false)
      add(:assignee, :text, null: false)
      add(:status, :text, null: false)
      add(:view, :text, null: false)
      add(:artifact, :text)
      add(:destination, :text)
      add(:action, :text)
      add(:optional, :boolean, null: false, default: false)
      add(:throwback, :text)
      add(:imported, :boolean, null: false, default: false)
      add(:waits_on, :integer)
      add(:reason, :text)
      add(:pin, :text)
      add(:approved_pin, :text)
      add(:result, :text)
      add(:note, :text)
      add(:ready_at, :utc_datetime_usec)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_queue_activity, [:household_id, :act_id]))
    create(index(:sunna_queue_activity, [:household_id, :assignee, :view]))

    projection :sunna_queue_history, scope: :platform do
      add(:id, :bigserial, primary_key: true)
      add(:household_id, :binary_id, null: false)
      add(:act_id, :text)
      add(:task, :integer, null: false)
      add(:what, :text, null: false)
      add(:outcome, :text)
      add(:pin, :text)
      add(:note, :text)
      add(:actor_kind, :text, null: false)
      add(:actor_id, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(index(:sunna_queue_history, [:household_id, :task, :at]))

    projection :sunna_queue_template, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:name, :text, null: false)
      add(:title, :text, null: false)
      add(:layers, :map, null: false)
      add(:defined_by, :text, null: false)
      add(:defined_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_queue_template, [:household_id, :name]))

    projection :sunna_queue_state, scope: :platform do
      add(:household_id, :binary_id, primary_key: true)
      add(:cut_over, :boolean, null: false, default: false)
      add(:cut_at, :utc_datetime_usec)
      add(:commit, :text)
      add(:via, :text)
      add(:note, :text)
    end
  end
end
