defmodule Oneiroi.Repo.Migrations.AgathosDaimonFiles do
  use Ecto.Migration
  import Oneiroi.Migration

  # The identity files and the proposals on them are the resident's rows
  # (spec §6.2); the steward reads them as the steward, checked at the
  # edge, under the resident's scope.
  def change do
    projection :agathos_daimon_file, scope: :resident do
      add(:name, :string, null: false)
      add(:content, :text, null: false)
      add(:origin, :string, null: false)
      add(:model, :string)
      add(:prompt, :text)
      add(:version, :integer, null: false, default: 1)
      add(:written_by_kind, :string)
      add(:written_by_id, :string)
      add(:written_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:agathos_daimon_file, [:resident_id, :name]))

    projection :agathos_daimon_soul_edit, scope: :resident do
      add(:ref, :string, null: false)
      add(:file, :string, null: false)
      add(:content, :text, null: false)
      add(:note, :text, null: false)
      add(:state, :string, null: false, default: "open")
      add(:proposed_by_kind, :string)
      add(:proposed_by_id, :string)
      add(:decided_note, :text)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:agathos_daimon_soul_edit, [:resident_id, :ref]))

    alter table(:agathos_daimon_resident) do
      add(:first_contact_at, :utc_datetime_usec)
      # Read only by the brain's prompt and the client's copy (spec §6.2):
      # the month after first contact in which proposals are presumed
      # welcome; never a gate.
      add(:formation_until, :utc_datetime_usec)
    end
  end
end
