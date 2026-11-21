defmodule Oneiroi.Repo.Migrations.MessageSealed do
  use Ecto.Migration

  # A turn answering a sealed letter (kumbukumbu#95): its messages' words
  # are the letter's parties', and a witness reads that they were said,
  # never what.
  def change do
    alter table(:kumbukumbu_message) do
      add(:sealed, :boolean, null: false, default: false)
    end
  end
end
