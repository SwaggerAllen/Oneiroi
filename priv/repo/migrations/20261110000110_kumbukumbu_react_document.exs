defmodule Oneiroi.Repo.Migrations.KumbukumbuReactDocument do
  use Ecto.Migration

  # Reacts on documents (kumbukumbu#61): the path reacted on and the hash
  # of the version it held then.
  def change do
    alter table(:kumbukumbu_react) do
      add(:path, :text)
      add(:document_hash, :string)
    end
  end
end
