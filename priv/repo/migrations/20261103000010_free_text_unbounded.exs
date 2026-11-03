defmodule Oneiroi.Repo.Migrations.FreeTextUnbounded do
  use Ecto.Migration

  # Free text is text, never varchar(255). A turn failed on a request
  # nearly twice the model's context, and the provider's refusal (some
  # 330 characters) was the CaptureFailed reason; the projector's insert
  # overflowed varchar(255), the handler stopped, the app restarted onto
  # the same event, and production crash-looped from 2026-11-03 14:30
  # UTC. Every column here holds words a model, a person or a third party
  # wrote, whose length nothing upstream bounds; Xenia's are a stranger's
  # to choose. varchar to text is a catalogue change in Postgres, no
  # rewrite.
  @columns [
    kumbukumbu_capture_failure: [:reason, :how],
    kumbukumbu_context_injection: [:reason, :label],
    kumbukumbu_bookmark: [:line],
    kumbukumbu_bookmark_proposal: [:line],
    kumbukumbu_session: [:label],
    seshat_document: [:title],
    sunna_checkin: [:label],
    sunna_date: [:title],
    huginn_muninn_counter: [:label],
    huginn_muninn_audit: [:label],
    gaia_token: [:label],
    xenia_message: [:external_id, :sender, :sender_name, :thread, :subject],
    xenia_block: [:identity, :name],
    xenia_reply: [:thread, :to]
  ]

  def up do
    for {table, columns} <- @columns do
      alter table(table) do
        for column <- columns, do: modify(column, :text)
      end
    end
  end

  def down do
    for {table, columns} <- @columns do
      alter table(table) do
        for column <- columns, do: modify(column, :string)
      end
    end
  end
end
