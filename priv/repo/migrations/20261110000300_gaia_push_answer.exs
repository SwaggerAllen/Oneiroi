defmodule Oneiroi.Repo.Migrations.GaiaPushAnswer do
  use Ecto.Migration
  import Oneiroi.Migration

  # The account's answer to the notifications question (gaia#25): the
  # latest of a device subscribing and the witness's "No thanks". While
  # an account has none (and no device), the question is on his
  # needs-you list (brain#76).
  def change do
    projection :gaia_push_answer, scope: :account do
      add(:state, :string, null: false)
      add(:answered_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:gaia_push_answer, [:account_id]))
  end
end
