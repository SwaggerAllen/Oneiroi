defmodule Oneiroi.Repo.Migrations.EunomiaRegressionTrace do
  use Ecto.Migration

  # A card shows the witness how its answer was reached (eunomia #31):
  # the trial's tool calls in order, string-keyed maps with the tool, its
  # arguments, read or mocked, and the result as cut. Additive, empty by
  # default: a card recorded before this kept no calls, and says none.
  def change do
    alter table(:eunomia_regression_answer) do
      add(:trace, {:array, :map}, null: false, default: [])
    end
  end
end
