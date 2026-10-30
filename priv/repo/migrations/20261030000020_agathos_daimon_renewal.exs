defmodule Oneiroi.Repo.Migrations.AgathosDaimonRenewal do
  use Ecto.Migration

  # The contract's renewal (spec §6.12, P5): when the version in force
  # was last renewed, and the note that came with it; due is derived on
  # read from this or the agreement's date, never stored.
  def change do
    alter table(:agathos_daimon_contract) do
      add(:renewed_at, :utc_datetime_usec)
      add(:renewal_note, :text)
    end
  end
end
