defmodule Oneiroi.Repo.Migrations.EunomiaRegressionRunFailed do
  use Ecto.Migration

  # A run answers in the background now (eunomia #30), so it can stop on
  # a fault after the request has gone: the run records when it failed
  # and the fault's site, so it ends rather than reading "running"
  # forever. Additive, nullable: a run finished before this has neither.
  def change do
    alter table(:eunomia_regression_run) do
      add(:failed_at, :utc_datetime_usec)
      add(:failure, :text)
    end
  end
end
