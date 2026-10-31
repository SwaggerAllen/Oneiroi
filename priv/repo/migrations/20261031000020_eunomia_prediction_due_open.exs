defmodule Oneiroi.Repo.Migrations.EunomiaPredictionDueOpen do
  use Ecto.Migration

  # A prediction carried from another platform may have been logged
  # without a date to resolve by (eunomia #29): five of Lily's ten in
  # David were. A live prediction still needs one; the aggregate holds
  # that, and this column no longer can.
  def change do
    alter table(:eunomia_prediction) do
      modify(:due, :utc_datetime_usec, null: true, from: {:utc_datetime_usec, null: false})
    end
  end
end
