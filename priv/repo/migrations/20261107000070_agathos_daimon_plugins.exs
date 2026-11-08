defmodule Oneiroi.Repo.Migrations.AgathosDaimonPlugins do
  use Ecto.Migration
  import Oneiroi.Migration

  # Plugins as contract material (agathos-daimon#37, brain#68): each
  # plugin's state for a resident, and every proposed change with the
  # other party's answer.
  def change do
    projection :agathos_daimon_plugin, scope: :resident do
      add(:key, :string, null: false)
      add(:tier, :text, null: false)
      add(:installed, :boolean, null: false, default: false)
      add(:on, :boolean, null: false, default: false)
      add(:carried_over, :boolean, null: false, default: false)
      add(:changed_by, :string)
      add(:changed_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:agathos_daimon_plugin, [:resident_id, :key]))

    projection :agathos_daimon_plugin_proposal, scope: :resident do
      add(:number, :integer, null: false)
      add(:key, :string, null: false)
      add(:tier, :text, null: false)
      add(:change, :text, null: false)
      add(:proposed_by, :string, null: false)
      add(:note, :text)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:agreed, :boolean)
      add(:answer_note, :text)
      add(:answered_by, :string)
      add(:answered_at, :utc_datetime_usec)
    end

    create(unique_index(:agathos_daimon_plugin_proposal, [:resident_id, :number]))
  end
end
