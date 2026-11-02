defmodule Oneiroi.Repo.Migrations.XeniaCorrespondence do
  use Ecto.Migration
  import Oneiroi.Migration

  # Correspondence (spec §6.6, F23 as amended; xenia #9): third parties'
  # messages, the blocked identities, and the resident's replies through
  # the gate.
  def change do
    projection :xenia_message, scope: :resident do
      add(:number, :integer, null: false)
      add(:platform, :string, null: false)
      add(:account, :string, null: false)
      add(:external_id, :string, null: false)
      add(:sender, :string, null: false)
      add(:sender_name, :string)
      add(:verified, :boolean, null: false, default: false)
      add(:thread, :string)
      add(:subject, :string)
      add(:text, :text)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:received_at, :utc_datetime_usec, null: false)
      add(:received_by, :string)
      add(:state, :string, null: false)
      add(:read_at, :utc_datetime_usec)
    end

    create(unique_index(:xenia_message, [:resident_id, :number]))
    create(unique_index(:xenia_message, [:resident_id, :platform, :account, :external_id]))

    projection :xenia_block, scope: :resident do
      add(:platform, :string, null: false)
      add(:identity, :string, null: false)
      add(:name, :string)
      add(:note, :text)
      add(:blocked_by, :string, null: false)
      add(:blocked_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:xenia_block, [:resident_id, :platform, :identity]))

    projection :xenia_reply, scope: :resident do
      add(:number, :integer, null: false)
      add(:in_reply_to, :integer)
      add(:platform, :string, null: false)
      add(:account, :string, null: false)
      add(:thread, :string)
      add(:to, :string, null: false)
      add(:text, :text, null: false)
      add(:state, :string, null: false)
      add(:note, :text)
      add(:drafted_at, :utc_datetime_usec, null: false)
      add(:decided_at, :utc_datetime_usec)
      add(:sent_at, :utc_datetime_usec)
      add(:sent_by, :string)
      add(:url, :text)
    end

    create(unique_index(:xenia_reply, [:resident_id, :number]))
  end
end
