defmodule Oneiroi.Repo.Migrations.GaiaTokenScope do
  use Ecto.Migration

  # A token's scope (gaia#40): nil is the account's whole reach, as every
  # token before; "ops" reads the operator's ops routes and nothing else
  # (apsu#30).
  def change do
    alter table(:gaia_token) do
      add(:scope, :string)
    end
  end
end
