defmodule Oneiroi.Repo.Migrations.EunomiaCriteria do
  use Ecto.Migration

  # The criteria a verdict was judged under (spec §6.4, P12): the hash of
  # the judge's prompt file, on the verdict's row beside its model. Null
  # on a quiet night judged by nobody.
  def change do
    for table <- [:eunomia_dispute, :eunomia_night, :eunomia_audit] do
      alter table(table) do
        add(:criteria, :string)
      end
    end
  end
end
