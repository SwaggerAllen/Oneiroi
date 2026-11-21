defmodule Oneiroi.Repo.Migrations.SeshatDocumentClass do
  use Ecto.Migration

  # A document's classification (seshat#102, kumbukumbu#85): the domain
  # its author set on it, a person's life and a domain slug, or the
  # common room (no domain), and when; null until classified, when its
  # birth decides.
  def change do
    alter table(:seshat_document) do
      add(:class_person, :text)
      add(:class_domain, :text)
      add(:classified_at, :utc_datetime_usec)
    end
  end
end
