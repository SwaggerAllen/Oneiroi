defmodule Oneiroi.Repo.Migrations.KumbukumbuDomain do
  use Ecto.Migration

  # The room a session is in (spec §6.3, P23): a domain slug, nil for
  # the common room; the index, the search, the madeleine and the lane's
  # exemplars respect it.
  def change do
    alter table(:kumbukumbu_session) do
      add(:domain, :string)
    end
  end
end
