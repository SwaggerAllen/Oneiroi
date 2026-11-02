defmodule Oneiroi.Repo.Migrations.KumbukumbuHouseLetter do
  use Ecto.Migration
  import Oneiroi.Migration

  # House letters (kumbukumbu #44): between conversations of one resident,
  # the resident's rows, read by the witness as the resident's witness.
  # `read_by` names the conversations that have read each.
  def change do
    projection :kumbukumbu_house_letter, scope: :resident do
      add(:number, :integer, null: false)
      add(:from_name, :string, null: false)
      add(:from_session, :string)
      add(:to_name, :string, null: false)
      add(:in_reply_to, :integer)
      add(:text, :text, null: false)
      add(:keepsake, :string)
      add(:by_kind, :string)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:read_by, {:array, :string}, null: false, default: [])
      add(:read_at, :utc_datetime_usec)
    end

    create(unique_index(:kumbukumbu_house_letter, [:resident_id, :number]))
  end
end
