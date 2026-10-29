defmodule Oneiroi.Repo.Migrations.AgathosDaimonImport do
  use Ecto.Migration

  # The import's second half on the row (agathos-daimon #25): whether the
  # attestation held, what did not transfer, and whether the resident
  # has been told. Told by default: a resident created here has nothing
  # to be oriented to, and only `ImportCompleted` drops the flag.
  def change do
    alter table(:agathos_daimon_resident) do
      add(:import_attestation, :string)
      add(:import_not_transferred, {:array, :string}, null: false, default: [])
      add(:import_told, :boolean, null: false, default: true)
    end
  end
end
