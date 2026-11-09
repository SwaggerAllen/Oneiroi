defmodule Oneiroi.Repo.Migrations.KumbukumbuReactBy do
  use Ecto.Migration

  # Reacts both ways (kumbukumbu#56, the witness's call 2026-11-09): who
  # reacted. Every react before this was the witness's, the only party
  # who could.
  def change do
    alter table(:kumbukumbu_react) do
      add(:by, :text, null: false, default: "witness")
    end
  end
end
