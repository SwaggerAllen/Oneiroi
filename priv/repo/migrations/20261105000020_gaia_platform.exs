defmodule Oneiroi.Repo.Migrations.GaiaPlatform do
  use Ecto.Migration
  import Oneiroi.Migration

  # The platform's own records (gaia#16): the front door, which belongs
  # to no account (platform-scoped, readable only by the platform), and
  # the roles accounts hold (account-scoped, each its holder's).
  def change do
    projection :gaia_gate, scope: :platform do
      add(:key, :string, primary_key: true)
      add(:state, :string, null: false)
      add(:note, :text)
      add(:set_by, :string)
      add(:set_at, :utc_datetime_usec, null: false)
    end

    projection :gaia_role, scope: :account do
      add(:role, :string, null: false)
      add(:note, :text)
      add(:granted_by, :string)
      add(:granted_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_role, [:account_id, :role]))
  end
end
