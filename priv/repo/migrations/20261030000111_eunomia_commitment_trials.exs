defmodule Oneiroi.Repo.Migrations.EunomiaCommitmentTrials do
  use Ecto.Migration

  # Trials derived from commitments (spec §6.4, §12, P19): a run lists
  # the commitments it drew on and a card names which one it answers
  # for, so the results score facts, voice and commitments apart.
  def change do
    alter table(:eunomia_regression_run) do
      add(:commitments, {:array, :bigint}, null: false, default: [])
    end

    alter table(:eunomia_regression_answer) do
      add(:commitment_number, :bigint)
    end
  end
end
