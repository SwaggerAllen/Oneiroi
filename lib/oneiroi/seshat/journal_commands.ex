defmodule Oneiroi.Seshat.JournalCommands do
  @moduledoc "The journal aggregate's commands; `id` is the resident's id."

  # `imported` (seshat #26): an entry carried from another platform's
  # notes keeps its words whatever their length; nothing but the import
  # sets it.
  defmodule AddJournalEntry do
    use Oneiroi.Command, fields: [:id, :day, :kind, :text, :register, :imported]
  end

  defmodule MarkTodoDone do
    use Oneiroi.Command, fields: [:id, :day, :number]
  end
end
