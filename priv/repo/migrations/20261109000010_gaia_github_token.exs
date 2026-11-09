defmodule Oneiroi.Repo.Migrations.GaiaGithubToken do
  use Ecto.Migration

  # The witness's GitHub read token (gaia#24), encrypted at rest beside
  # the OpenRouter key, set and revoked from the client.
  def change do
    alter table(:gaia_account) do
      add(:github_token_ciphertext, :binary)
      add(:github_token_stored_at, :utc_datetime_usec)
    end
  end
end
