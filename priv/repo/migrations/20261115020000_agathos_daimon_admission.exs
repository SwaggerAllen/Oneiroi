defmodule Oneiroi.Repo.Migrations.AgathosDaimonAdmission do
  use Ecto.Migration

  # Formation (agathos-daimon#46): who may reach a resident. `open` for
  # every resident made before it; `forming` until the witness wakes one
  # made through the creation flow, `witness_only` until their first
  # agreement is in force.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:admission, :text, null: false, default: "open")
    end
  end
end
