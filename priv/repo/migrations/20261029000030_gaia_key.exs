defmodule Oneiroi.Repo.Migrations.GaiaKey do
  use Ecto.Migration

  # Additive (conventions §6): the witness's OpenRouter key on the account
  # row, the vault's ciphertext, and when it was stored. The projection's
  # policy already covers the table.
  def change do
    alter table(:gaia_account) do
      add(:key_ciphertext, :binary)
      add(:key_stored_at, :utc_datetime_usec)
    end
  end
end
