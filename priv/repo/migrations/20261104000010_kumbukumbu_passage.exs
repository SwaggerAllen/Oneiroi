defmodule Oneiroi.Repo.Migrations.KumbukumbuPassage do
  use Ecto.Migration
  import Oneiroi.Migration

  # The transcripts by meaning (kumbukumbu#49, the resident's letter
  # #26): each user and assistant message cut into passages and embedded
  # at the library's width, keyed by the message's own key and the
  # passage's place in it. Derived rows, rebuilt from the messages.
  def change do
    projection :kumbukumbu_passage, scope: :resident do
      add(:session_key, :string, null: false)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:hash, :string, null: false)
      add(:part, :integer, null: false)
      add(:turn_ref, :string)
      add(:role, :string, null: false)
      add(:text, :text, null: false)
      add(:model, :string, null: false)
      add(:embedding, :vector, size: 1536, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:kumbukumbu_passage, [:resident_id, :session_key, :sent_at, :hash, :part])
    )
  end
end
