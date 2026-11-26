defmodule Oneiroi.Repo.Migrations.NisabaModel do
  use Ecto.Migration
  import Oneiroi.Migration

  def change do
    # The provider's list, priced, fetched each night (nisaba#24): the
    # platform's own, no tenant's.
    projection :nisaba_model, scope: :platform do
      add(:model_id, :text, primary_key: true)
      add(:name, :text)
      add(:description, :text)
      add(:input_nanos, :bigint, null: false)
      add(:output_nanos, :bigint, null: false)
      add(:context, :bigint)
      add(:tools, :boolean, null: false, default: false)
      add(:fetched_at, :utc_datetime_usec, null: false)
    end
  end
end
