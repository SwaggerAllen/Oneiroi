defmodule Oneiroi.Repo.Migrations.Kumbukumbu do
  use Ecto.Migration
  import Oneiroi.Migration

  # Every table is scoped both ways (spec §6.3's visibility rule as a
  # policy): the resident's id, and the account party to the session.
  def change do
    projection :kumbukumbu_session, scope: :both do
      add(:key, :string, null: false)
      add(:kind, :string, null: false)
      add(:adapter, :string)
      add(:participants, {:array, :string}, null: false, default: [])
      add(:shared, :boolean, null: false, default: false)
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:last_turn_at, :utc_datetime_usec)
      add(:turns, :integer, null: false, default: 0)
    end

    create(unique_index(:kumbukumbu_session, [:resident_id, :key]))
    create(index(:kumbukumbu_session, [:account_id, :opened_at]))

    # Keyed as David's message table is (spec §3.2): session, sent_at and
    # the content's hash, so a turn captured twice is one row set.
    projection :kumbukumbu_message, scope: :both do
      add(:session_key, :string, null: false)
      add(:sent_at, :utc_datetime_usec, null: false)
      add(:hash, :string, null: false)
      add(:turn_ref, :string, null: false)
      # The order the transcript reads in: the capture's place in the log
      # and the message's place in its turn. Instants are not an order:
      # two messages of one turn can share one, and the suite's fake
      # clock gives every message the same.
      add(:sequence, :bigint, null: false, default: 0)
      add(:position, :integer, null: false, default: 0)
      add(:role, :string, null: false)
      add(:actor_kind, :string)
      add(:actor_id, :string)
      add(:model, :string)
      add(:content, :text, null: false)
      add(:refusal, :boolean, null: false, default: false)
    end

    create(unique_index(:kumbukumbu_message, [:resident_id, :session_key, :sent_at, :hash]))
    create(index(:kumbukumbu_message, [:resident_id, :turn_ref]))
    create(index(:kumbukumbu_message, [:resident_id, :session_key, :sequence, :position]))

    projection :kumbukumbu_capture_failure, scope: :both do
      add(:turn_ref, :string, null: false)
      add(:session_key, :string, null: false)
      add(:reason, :string, null: false)
      add(:failed_at, :utc_datetime_usec, null: false)
      add(:resolved_at, :utc_datetime_usec)
      add(:how, :string)
    end

    create(unique_index(:kumbukumbu_capture_failure, [:resident_id, :turn_ref]))

    projection :kumbukumbu_context_injection, scope: :both do
      add(:turn_ref, :string, null: false)
      add(:position, :integer, null: false)
      add(:session_key, :string, null: false)
      add(:label, :string, null: false)
      add(:tokens, :integer, null: false, default: 0)
      add(:reason, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_context_injection, [:resident_id, :turn_ref, :position]))
  end
end
