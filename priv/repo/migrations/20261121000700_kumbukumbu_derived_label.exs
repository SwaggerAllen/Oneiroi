defmodule Oneiroi.Repo.Migrations.KumbukumbuDerivedLabel do
  use Ecto.Migration
  import Oneiroi.Migration

  # A record's labels derived again from the messages it came from
  # (kumbukumbu#101): what every reader prefers over the copy kept at
  # write time, which stays as history.
  def change do
    projection :kumbukumbu_derived_label, scope: :resident do
      add(:kind, :string, null: false)
      add(:record_id, :string, null: false)
      add(:labels, {:array, :map}, null: false, default: [])
      add(:edges, {:array, :map}, null: false, default: [])
      add(:derived_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_derived_label, [:resident_id, :kind, :record_id]))
  end
end
