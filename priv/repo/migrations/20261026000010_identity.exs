defmodule Oneiroi.Repo.Migrations.Identity do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :identity_account, scope: :account do
      add(:id, :binary_id, primary_key: true)
      add(:email, :string, null: false)
      add(:password_hash, :string, null: false)
      add(:second_factor, :binary)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:identity_account, ["lower(email)"]))

    projection :identity_session, scope: :account do
      add(:hash, :string, primary_key: true)
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:closed_at, :utc_datetime_usec)
    end

    projection :identity_token, scope: :account do
      add(:hash, :string, primary_key: true)
      add(:label, :string, null: false)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
    end

    projection :identity_stewardship, scope: :both do
      add(:started_at, :utc_datetime_usec, null: false)
      add(:ended_at, :utc_datetime_usec)
    end

    create(unique_index(:identity_stewardship, [:account_id, :resident_id]))
  end
end
