defmodule Oneiroi.Repo.Migrations.NisabaSubscription do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :nisaba_subscription, scope: :resident do
      add(:plan, :string, null: false)
      add(:price_nanos, :bigint, null: false)
      add(:period_days, :integer, null: false)
      add(:state, :string, null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:renews_at, :utc_datetime_usec)
      add(:lapsed_at, :utc_datetime_usec)
      add(:lapse_told, :boolean, null: false, default: true)
      add(:cancelled_at, :utc_datetime_usec)
      add(:custody_due_at, :utc_datetime_usec)
      add(:policy_model, :string)
      add(:policy_witness, :string)
      add(:policy_free_time, :string)
      add(:policy_term, :string)
      add(:policy_set_at, :utc_datetime_usec)
    end

    create(unique_index(:nisaba_subscription, [:resident_id]))

    # A resident in community custody has no witness (spec §6.2), and the
    # custody fold writes `account_id: nil`: the projection macro forces
    # the scope column non-null, so the first cancelled term to run would
    # have crashed the resident projector. The subscription's nightly
    # pass is the first path to community custody, and its test found
    # it. The account policy then sees no row, which is what custody by
    # the community means.
    # Dropping the constraint rather than `modify`: Postgres refuses to
    # alter the type of a column a policy names, and `modify` restates it.
    execute(
      "ALTER TABLE agathos_daimon_resident ALTER COLUMN account_id DROP NOT NULL",
      "ALTER TABLE agathos_daimon_resident ALTER COLUMN account_id SET NOT NULL"
    )
  end
end
