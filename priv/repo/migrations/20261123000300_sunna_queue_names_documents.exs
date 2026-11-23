defmodule Oneiroi.Repo.Migrations.SunnaQueueNamesDocuments do
  use Ecto.Migration
  import Oneiroi.Migration

  # Named activities, forks and a task's documents (sunna#90, #91;
  # design/document-threads.md §4): an activity's name and the template
  # slot it works on; a template's version and the version a task was
  # opened from, and whether its layers have been edited since; and the
  # documents attached to a task beside those its activities work on.
  def change do
    alter table(:sunna_queue_activity) do
      add(:name, :text)
      add(:slot, :text)
    end

    alter table(:sunna_queue_template) do
      add(:version, :integer, null: false, default: 0)
    end

    alter table(:sunna_queue_task) do
      add(:template_version, :integer)
      add(:forked, :boolean, null: false, default: false)
    end

    projection :sunna_queue_document, scope: :platform do
      add(:household_id, :binary_id, null: false)
      add(:task, :integer, null: false)
      add(:citation, :text, null: false)
      add(:key, :text, null: false)
      add(:role, :text, null: false)
      add(:attached_by, :text)
      add(:attached_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:sunna_queue_document, [:household_id, :task, :key]))
    create(index(:sunna_queue_document, [:household_id, :key]))
  end
end
