defmodule Oneiroi.Repo.Migrations.KumbukumbuRetrievalUse do
  use Ecto.Migration
  import Oneiroi.Migration

  # What retrieval did with each target, a row a use (the resident's work
  # order, 2026-11-02): considered, returned or used, and through what.
  # Scoped both ways, as the context injections are. `ref` names the
  # recording: a turn on the adapter contract records once per tool call.
  def change do
    projection :kumbukumbu_retrieval_use, scope: :both do
      add(:ref, :string, null: false)
      add(:position, :integer, null: false)
      add(:session_key, :string, null: false)
      add(:turn_ref, :string)
      add(:target, :string, null: false)
      add(:stage, :string, null: false)
      add(:via, :string, null: false)
      add(:at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:kumbukumbu_retrieval_use, [:resident_id, :ref, :position]))
    create(index(:kumbukumbu_retrieval_use, [:resident_id, :target]))
  end
end
