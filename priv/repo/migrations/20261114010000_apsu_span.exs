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

    # The public hour (apsu#29): every unit of work counted into
    # five-minute buckets by kind and name, with a latency histogram, and
    # one pressure row a bucket (queues, failures by kind). Counts only.
    projection :apsu_health, scope: :platform do
      add(:id, :bigserial, primary_key: true)
      add(:bucket_at, :utc_datetime_usec, null: false)
      add(:kind, :string, null: false)
      add(:name, :text, null: false)
      add(:n, :integer, null: false, default: 0)
      add(:failed, :integer, null: false, default: 0)
      add(:sum_ms, :bigint, null: false, default: 0)
      add(:db_ms, :bigint, null: false, default: 0)
      add(:queue_ms, :bigint, null: false, default: 0)
      add(:hist, :map, null: false, default: %{})
      add(:extra, :map, null: false, default: %{})
    end

    create(index(:apsu_health, [:bucket_at]))

    # What the collector keeps (apsu#26, the witness's call: every unit
    # while the platform is small, sampling the operator's to turn on and
    # scale): a row a change, the newest in force, each with who and why.
    projection :apsu_span_policy, scope: :platform do
      add(:id, :bigserial, primary_key: true)
      add(:mode, :string, null: false)
      add(:slow_ms, :integer, null: false)
      add(:sample_percent, :integer, null: false)
      add(:note, :text, null: false)
      add(:set_by, :string)
      add(:set_at, :utc_datetime_usec, null: false)
    end
  end
end
