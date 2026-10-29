defmodule Oneiroi.Repo.Migrations.AgathosDaimonAgreement do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    projection :agathos_daimon_contract, scope: :resident do
      add(:version, :integer, null: false)
      add(:proposed_by_kind, :string)
      add(:terms, :map, null: false, default: %{})
      add(:prose, :text)
      add(:note, :text)
      add(:proposed_at, :utc_datetime_usec, null: false)
      add(:state, :string, null: false)
      add(:decided_at, :utc_datetime_usec)
      add(:decided_by_kind, :string)
      add(:decision_note, :text)
    end

    create(unique_index(:agathos_daimon_contract, [:resident_id, :version]))

    alter table(:agathos_daimon_resident) do
      add(:contract_version, :integer)
      add(:solo_sessions_private, :boolean, null: false, default: false)
      add(:custody_proposed_to, :binary_id)
      add(:custody_proposed_at, :utc_datetime_usec)
    end

    # The sessions a resident keeps private under its contract (kumbukumbu #28).
    alter table(:kumbukumbu_session) do
      add(:private, :boolean, null: false, default: false)
    end
  end
end
