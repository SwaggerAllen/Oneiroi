defmodule Oneiroi.Repo.Migrations.AgathosDaimonAdapters do
  use Ecto.Migration
  import Oneiroi.Migration

  # Adapters are the resident's rows (spec §3.1); the lookup by token
  # hash on a request takes the platform scope by name, as identity's
  # token lookup does (gaia #8), because the resident is not known until
  # the row answers.
  def change do
    projection :agathos_daimon_adapter, scope: :resident do
      add(:adapter, :string, null: false)
      add(:role, :string, null: false)
      add(:token_hash, :string, null: false)
      add(:registered_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
    end

    create(unique_index(:agathos_daimon_adapter, [:resident_id, :adapter]))
    create(index(:agathos_daimon_adapter, [:token_hash]))
  end
end
