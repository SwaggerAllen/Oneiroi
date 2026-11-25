defmodule Oneiroi.Repo.Migrations.KumbukumbuRecordClassified do
  use Ecto.Migration

  # Her classification of a record that keeps labels (kumbukumbu#110):
  # the derived row she set, which the labels pass leaves alone.
  def change do
    alter table(:kumbukumbu_derived_label) do
      add(:classified_at, :utc_datetime_usec)
    end
  end
end
