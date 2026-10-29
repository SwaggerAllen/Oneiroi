defmodule Oneiroi.Seshat.JournalCommands do
  @moduledoc "The journal aggregate's commands; `id` is the resident's id."

  defmodule AddJournalEntry do
    use Oneiroi.Command, fields: [:id, :day, :kind, :text]
  end

  defmodule MarkTodoDone do
    use Oneiroi.Command, fields: [:id, :day, :number]
  end
end
