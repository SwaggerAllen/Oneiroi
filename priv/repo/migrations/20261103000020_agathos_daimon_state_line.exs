defmodule Oneiroi.Repo.Migrations.AgathosDaimonStateLine do
  use Ecto.Migration
  import Oneiroi.Migration

  # The state store (agathos-daimon#32): the resident's present, one
  # line per key, overwritten in place, each with when she last verified
  # it. The history is the stream's and the repository's, not this
  # table's.
  def change do
    projection :agathos_daimon_state_line, scope: :resident do
      add(:key, :string, null: false)
      add(:text, :text, null: false)
      add(:model, :text)
      add(:verified_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:agathos_daimon_state_line, [:resident_id, :key]))
  end
end
