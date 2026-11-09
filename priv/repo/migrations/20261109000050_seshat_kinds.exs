defmodule Oneiroi.Repo.Migrations.SeshatKinds do
  use Ecto.Migration
  import Oneiroi.Migration

  # A resident's own kinds and the system kinds' gates (seshat#51): the
  # descriptors in her folders, projected; the gate as hers where it
  # moved; the proposals to turn one off.
  def change do
    projection :seshat_user_kind, scope: :resident do
      add(:kind, :text, null: false)
      add(:descriptor, :map, null: false)
      add(:created_by, :text)
      add(:updated_by, :text)
      add(:created_at, :utc_datetime_usec, null: false)
      add(:updated_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:seshat_user_kind, [:resident_id, :kind]))

    projection :seshat_kind_gate, scope: :resident do
      add(:kind, :text, null: false)
      add(:approvable, :boolean, null: false)
      add(:moved_by, :text)
      add(:moved_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:seshat_kind_gate, [:resident_id, :kind]))

    projection :seshat_kind_gate_proposal, scope: :resident do
      add(:number, :integer, null: false)
      add(:kind, :text, null: false)
      add(:approvable, :boolean, null: false)
      add(:proposed_by, :text)
      add(:note, :text)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:agree, :boolean)
      add(:answered_by, :text)
      add(:answer_note, :text)
      add(:answered_at, :utc_datetime_usec)
    end

    create(unique_index(:seshat_kind_gate_proposal, [:resident_id, :number]))
  end
end
