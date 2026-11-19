defmodule Oneiroi.Repo.Migrations.GaiaSeen do
  use Ecto.Migration
  import Oneiroi.Migration

  # How far a witness has read (gaia#58): a row per conversation or thread,
  # the newest instant they had on screen. The witness's own, account-scoped.
  def change do
    projection :gaia_seen, scope: :account do
      add(:subject, :text, null: false)
      add(:key, :text, null: false)
      add(:seen_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_seen, [:account_id, :subject, :key]))
  end
end
