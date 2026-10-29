defmodule Oneiroi.Repo.Migrations.Nisaba do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    # One line per purpose per resident; the natural key is the unique
    # index, and the row is written by the projector from the event's
    # own fields, which is why there is no generated id.
    projection :nisaba_budget, scope: :resident do
      add(:purpose, :string, null: false)
      add(:cap_nanos, :bigint)
      add(:period, :string, null: false)
      add(:set_at, :utc_datetime_usec, null: false)
      add(:exceeded_period_key, :string)
      add(:exceeded_at, :utc_datetime_usec)
    end

    create(unique_index(:nisaba_budget, [:resident_id, :purpose]))

    # One row per model call, keyed by the call's own id so a replay
    # writes it once. Spend per period is a range scan on the index.
    projection :nisaba_usage, scope: :resident do
      add(:ref, :binary_id, primary_key: true)
      add(:purpose, :string, null: false)
      add(:model, :string)
      add(:actor_kind, :string, null: false)
      add(:actor_id, :string)
      add(:prompt_tokens, :integer, null: false, default: 0)
      add(:completion_tokens, :integer, null: false, default: 0)
      add(:cost_nanos, :bigint, null: false, default: 0)
      add(:estimated, :boolean, null: false, default: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(index(:nisaba_usage, [:resident_id, :purpose, :at]))
    create(index(:nisaba_usage, [:resident_id, :at]))
  end
end
