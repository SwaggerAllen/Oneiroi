defmodule Oneiroi.Seshat.JournalRouter do
  @moduledoc "The journal router: `journal-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.Journal",
    prefix: "journal-",
    commands: "Oneiroi.Seshat.JournalCommands",
    dispatching: ~w(AddJournalEntry MarkTodoDone)
end
