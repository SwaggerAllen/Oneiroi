defmodule Oneiroi.Repo.Migrations.JanusEnvelopeMaxModels do
  use Ecto.Migration

  # How many models the envelope lets into the pool (janus#40), nil for
  # no cap: stated with the envelope, by the witness.
  def change do
    alter table(:janus_succession) do
      add(:envelope_max_models, :integer)
    end
  end
end
