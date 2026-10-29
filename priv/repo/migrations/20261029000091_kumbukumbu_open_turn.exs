defmodule Oneiroi.Repo.Migrations.KumbukumbuOpenTurn do
  use Ecto.Migration

  # The adapter contract's open turn (spec §8): set by TurnStarted,
  # cleared by the capture that carries the same ref.
  def change do
    alter table(:kumbukumbu_session) do
      add(:open_turn_ref, :string)
    end
  end
end
