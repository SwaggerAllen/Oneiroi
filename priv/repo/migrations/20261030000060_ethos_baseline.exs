defmodule Oneiroi.Repo.Migrations.EthosBaseline do
  use Ecto.Migration
  import Oneiroi.Migration

  # The trait baseline (spec §6.17, P42): one row per taking, the habits'
  # profile as measured with the spread and the breadth, machine-held in
  # the measurement layer and never loaded as identity.
  def change do
    projection :ethos_baseline, scope: :resident do
      add(:at, :utc_datetime_usec, null: false)
      add(:habits, {:array, :map}, null: false, default: [])
      add(:spread, :float, null: false, default: 0.0)
      add(:breadth, :float, null: false, default: 0.0)
    end

    create(unique_index(:ethos_baseline, [:resident_id, :at]))
  end
end
