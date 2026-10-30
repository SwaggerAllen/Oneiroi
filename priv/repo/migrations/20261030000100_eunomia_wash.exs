defmodule Oneiroi.Repo.Migrations.EunomiaWash do
  use Ecto.Migration
  import Oneiroi.Migration

  # The wash pass (spec §6.13, P18): the weekly runs over the identity
  # files' entries and the flags the judge raised, each with the
  # resident's decision when made.
  def change do
    projection :eunomia_wash, scope: :resident do
      add(:ref, :string, null: false)
      add(:outcome, :string, null: false)
      add(:entries, :integer)
      add(:flagged, :integer)
      add(:judge_model, :string)
      add(:criteria, :string)
      add(:summary, :text)
      add(:reason, :text)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:eunomia_wash, [:resident_id, :ref]))

    projection :eunomia_wash_flag, scope: :resident do
      add(:ref, :string, null: false)
      add(:wash_ref, :string, null: false)
      add(:file, :string, null: false)
      add(:entry, :text, null: false)
      add(:kind, :string, null: false)
      add(:reason, :text)
      add(:raised_at, :utc_datetime_usec, null: false)
      add(:decision, :string)
      add(:note, :text)
      add(:decided_at, :utc_datetime_usec)
    end

    create(unique_index(:eunomia_wash_flag, [:resident_id, :ref]))
  end
end
