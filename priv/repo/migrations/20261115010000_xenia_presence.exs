defmodule Oneiroi.Repo.Migrations.XeniaPresence do
  use Ecto.Migration
  import Oneiroi.Migration

  # Presence (xenia#20): the witness's switch and handle, the follow list
  # with its mask and each account's last sample, the day's passes and
  # their reads, and the interactions on their way to being sent.
  def change do
    projection :xenia_presence, scope: :resident do
      add(:enabled, :boolean, null: false, default: false)
      add(:handle, :text)
      add(:set_at, :utc_datetime_usec)
      add(:follows_at, :utc_datetime_usec)
      add(:visible, :integer)
      add(:cursor, :text)
    end

    create(unique_index(:xenia_presence, [:resident_id]))

    projection :xenia_presence_account, scope: :resident do
      add(:key, :text, null: false)
      add(:name, :text)
      add(:host, :text, null: false)
      add(:publication_id, :bigint)
      add(:author_id, :bigint)
      add(:first_seen_at, :utc_datetime_usec, null: false)
      add(:followed, :boolean, null: false, default: true)
      add(:last_sampled_at, :utc_datetime_usec)
      add(:excluded, :boolean, null: false, default: false)
      add(:excluded_at, :utc_datetime_usec)
      add(:reason, :text)
    end

    create(unique_index(:xenia_presence_account, [:resident_id, :key]))

    projection :xenia_presence_pass, scope: :resident do
      add(:number, :integer, null: false)
      add(:day, :text, null: false)
      add(:accounts, {:array, :text}, null: false, default: [])
      add(:pool, :integer, null: false)
      add(:ranked, :integer, null: false)
      add(:serendipity, :integer, null: false)
      add(:cap, :integer, null: false)
      add(:drawn_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:xenia_presence_pass, [:resident_id, :number]))

    projection :xenia_presence_read, scope: :resident do
      add(:pass, :integer, null: false)
      add(:item, :text, null: false)
      add(:account, :text, null: false)
      add(:kind, :text, null: false)
      add(:title, :text)
      add(:url, :text, null: false)
      add(:published_at, :utc_datetime_usec)
      add(:likes, :integer, null: false, default: 0)
      add(:comments, :integer, null: false, default: 0)
      add(:restacks, :integer, null: false, default: 0)
      add(:score, :integer, null: false, default: 0)
      add(:cut, :text, null: false)
      add(:excerpt, :text)
      add(:read_at, :utc_datetime_usec)
    end

    create(unique_index(:xenia_presence_read, [:resident_id, :pass, :item]))

    projection :xenia_presence_interaction, scope: :resident do
      add(:number, :integer, null: false)
      add(:pass, :integer, null: false)
      add(:item, :text, null: false)
      add(:account, :text, null: false)
      add(:kind, :text, null: false)
      add(:text, :text)
      add(:supersedes, :integer)
      add(:superseded_by, :integer)
      add(:state, :text, null: false)
      add(:comment, :text)
      add(:release_at, :utc_datetime_usec)
      add(:staged_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
      add(:sent_at, :utc_datetime_usec)
      add(:url, :text)
      add(:reason, :text)
    end

    create(unique_index(:xenia_presence_interaction, [:resident_id, :number]))
  end
end
