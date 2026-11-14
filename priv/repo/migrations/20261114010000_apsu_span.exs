defmodule Oneiroi.Repo.Migrations.ApsuSpan do
  use Ecto.Migration
  import Oneiroi.Migration

  # The span collector (apsu#26): a request, job or turn that was slow,
  # or sampled, with its totals and its slowest exports. The platform's
  # own record, no words: names, numbers, the resident it served and the
  # trace that joins it to the events it caused.
  def change do
    projection :apsu_span, scope: :platform do
      add(:id, :bigserial, primary_key: true)
      add(:at, :utc_datetime_usec, null: false)
      add(:kind, :string, null: false)
      add(:name, :text, null: false)
      add(:subject_id, :binary_id)
      add(:trace_id, :string)
      add(:duration_ms, :integer, null: false)
      add(:db_count, :integer, null: false, default: 0)
      add(:db_ms, :integer, null: false, default: 0)
      add(:queue_ms, :integer, null: false, default: 0)
      add(:exports, :map, null: false, default: %{})
      # The events the unit dispatched, by name and count (apsu#27).
      add(:events, :map, null: false, default: %{})
      add(:failed, :boolean, null: false, default: false)
      add(:sampled, :boolean, null: false, default: false)
    end

    create(index(:apsu_span, [:at]))
    create(index(:apsu_span, [:name, :at]))
    create(index(:apsu_span, [:trace_id]))
  end
end
