defmodule Oneiroi.Repo.Migrations.GaiaInvite do
  use Ecto.Migration
  import Oneiroi.Migration

  # Invite codes (gaia#18): the platform's own, like the front door they
  # open, so platform-scoped; the code is held only as its hash.
  def change do
    projection :gaia_invite, scope: :platform do
      add(:id, :binary_id, primary_key: true)
      add(:code_hash, :string, null: false)
      add(:plan, :text, null: false)
      add(:price_nanos, :bigint, null: false)
      add(:discount_pct, :integer, null: false)
      add(:term_days, :integer, null: false)
      add(:uses, :integer, null: false)
      add(:redeemed, :integer, null: false, default: 0)
      add(:expires_at, :utc_datetime_usec)
      add(:note, :text)
      add(:issued_by, :string)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)
      add(:revoke_note, :text)
    end

    create(unique_index(:gaia_invite, [:code_hash]))

    projection :gaia_invite_redemption, scope: :platform do
      add(:invite_id, :binary_id, null: false)
      add(:household_id, :binary_id, null: false)
      add(:redeemed_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_invite_redemption, [:invite_id, :household_id]))
  end
end
